# Encrypted daily backup and isolated recovery

Assumptions: dedicated Linux VPS, MySQL/InnoDB, all DB/asset writers inventoried,
a daily owner-approved closed-shop hour and a separate recovery host. Daily
snapshots provide **up to 24 hours RPO when successful**, not a 15-minute RPO.
Failures make that worse. Record actual restore elapsed time rather than claim
an untested RTO. Unsynced tablet-only orders are not in a server backup. A lower
RPO needs a separately tested binlog/replica/asset recovery design.

## Keys and credentials

On an owner's trusted **recovery machine, never on the application VPS**:

```sh
umask 077
age-keygen -o /secure-recovery/top-coffee.agekey
age-keygen -y /secure-recovery/top-coffee.agekey > /secure-recovery/top-coffee-recipients.txt
```

`umask` makes newly created files private; age-keygen creates a real private
identity and the second command derives the public recipient. Create the private
parent directory first in the owner's encrypted recovery volume. Neither command
has been run for the owner. Copy **only the public recipient file** to the backup
VPS. Store the private identity in two independently recoverable places outside
the app server: an owner-controlled encrypted password/secret vault and an offline
encrypted recovery copy held by the named deputy. Store vault recovery material
independently. Do not put private age keys in the application server, its backups,
Git, CI artifacts, email or chat. Also retain APP_KEY, provider recovery codes,
DB recovery access and signing material in the appropriate independent vaults.

Create an actual scoped off-site account/remote privately with `rclone config
--config /etc/top-coffee/rclone.conf`. This interactive command stores the real
provider credentials; its file must be mode 600. Scope it to the backup prefix,
allow upload/read for verification, deny delete and turn on provider-side
immutability/versioning/lifecycle through a separate owner account. An obscured
rclone password is not a substitute for private file permissions.

The VPS gets a private MySQL backup-client.cnf with [client] connection details,
public age recipients and scoped off-site credentials. Runtime has no backup
or recovery credentials. On MySQL 8 use mysqldump's least-privilege needs as
actually exercised by tools/mysql_backup.py; test SHOW GRANTS and backup as that
account on staging, rather than grant ALL. Recovery CREATE/DROP is for the
isolated recovery instance only.

## Daily job, drain and off-site verification

Create backup.json from deploy/backup.config.example.json in /etc/top-coffee,
mode 600/root-owned. Blank remote and commit intentionally refuse execution.
Supply the deployed exact commit (update after activation), real named rclone
remote/prefix, actual paths and list every writer. Approve the UTC hour only
after confirming **every branch is closed**; 20:00 UTC is 03:00 next day in
Asia/Phnom_Penh and is an example schedule, not an assumed shop closing time.
Disable any crontab, alternate scheduler or external integration writer that
would bypass the listed systemd units. Include the scheduler timer and currently
running service, workers and dedicated FPM service. Prove graceful stop/drain on
staging; do not assert --writes-drained while trading.

```sh
python3 deploy/daily_backup.py --config /etc/top-coffee/backup.json
```

This prints the plan only. It neither connects to MySQL nor stops services.

```sh
sudo python3 deploy/daily_backup.py --config /etc/top-coffee/backup.json --execute
```

During the approved UTC hour this locks against concurrent jobs, remembers active
writer units, stops them, runs the existing authenticated age-encrypted backup,
and attempts **all** service restarts in finally. It restarts only units that
were active. It then uploads the .age file using immutable rclone copyto and
streams the remote ciphertext back through SHA-256 before recording a private
success receipt. SQL/assets exist only in a private temporary staging directory;
the published spool holds ciphertext and nonsecret evidence. The embedded
manifest records source commit, every table count, deterministic data hash and
asset hashes. Temp files are cleaned on normal failure, not guaranteed secure
erasure or survival of an OS crash: protect the host volume, disk access and
reboot recovery. Check services/partial staging after a kill or power loss.

A failed upload keeps local ciphertext, publishes no success receipt and alerts.
A backup/restart failure exits nonzero and sends a fixed backup_failed message;
service OnFailure is an additional delivery attempt, so duplicates can occur.
No remote object or unverified local backup is automatically deleted. A
nonzero exit must be investigated even if a snapshot file exists.

Install the reviewed backup.service/timer only after a successful staging run
and owner approval. Edit timer UTC hour to exactly match private backup.json.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now top-coffee-backup.timer
systemctl list-timers top-coffee-backup.timer
```

These load reviewed units, **schedule the real daily job**, then display its next
run. They are owner/operator steps; not executed by this PR. Persistent=false
prevents catch-up pauses during trading; the independent backup-freshness monitor
must page if a run was missed. The app-host failure job cannot detect a wholly
dead host. Configure the external provider monitor for a verified receipt no
older than 26 hours and independently monitor its own delivery. That provider
configuration is still an owner task, not functionality claimed by this script.

## Proposed retention (requires owner approval)

Keep seven days locally, always at least two newest off-site-verified snapshots.
`retention_approved=false` leaves automatic local pruning disabled. Only set true
after approval. Local pruning only considers receipts for verified copies; it
never removes unverified backups. Keep 30 days off-site through provider lifecycle
and object lock, managed by a separate owner account. Longer accounting/legal
record retention must be selected with the owner's adviser; 30-day backups are
not a promise of compliance or a substitute for accounting archives. Reconcile
privacy deletion requests with backup expiry and prevent restoring deleted
personal data into active service without applying the deletion register.

## Recovery-host scratch restore and row-count proof

Retrieve one encrypted object onto the **separate recovery machine** with its
own read-only retrieval credentials:

```sh
rclone --config /secure-recovery/rclone.conf copyto "$REMOTE_OBJECT" /secure-recovery/rehearsal.age --immutable
```

This copies one chosen real remote ciphertext without overwriting a different
local file. Set REMOTE_OBJECT to an actual retained object, not an application
URL. Restrict the local directory to mode 700. Use private recovery-client.cnf
(mode 600) for an **isolated MySQL instance**, never production DB credentials.

```sh
python3 backend-skeleton/tools/restore_test.py --credentials /secure-recovery/recovery-client.cnf --backup /secure-recovery/rehearsal.age --identity /secure-recovery/top-coffee.agekey --work-root /secure-recovery/work
```

This authenticates the whole encrypted archive **before contacting MySQL**,
creates a unique pos_recovery_*_restore database, refuses existing-target
replacement, imports and compares **all table counts, data hash and asset hashes**.
It prints row-count and elapsed-time evidence. Scratch data is retained for
reconciliation; the failure path also retains partial DB/assets for investigation.
Add `--drop-on-success` only to delete this command-generated DB/assets after every
comparison passes; failures never trigger that cleanup. The private decryption
workspace is temporary and cleaned on exit. Use --max-archive-bytes only after
reviewing recovery disk budget; default is 20 GiB.

Manual acceptance must reconcile order/payment/refund/stock totals and inspect
receipt assets; row counts alone do not prove money integrity. Record elapsed
recovery, source commit/time, last recoverable sale and owner sign-off. Repeat
monthly and before significant schema/storage changes. Never point a restored
scratch DB at real payment/webhook/alert integrations. No existing production
DB is overwritten and no financial down-migrations are part of this workflow.

## Automated proof

`bash tools/test_mysql_backup.sh` from backend-skeleton is deliberately guarded
for CI disposable MySQL only. It covers Khmer/decimal rows/assets, authenticated
encrypted backup and restore, rejection of source/populated targets, and the
fresh scratch restore command with cleanup after verified success. Python tests
cover malformed archives, corruption/authentication, private keys and traversal.
`deploy/tests/test_operations.py` covers service recovery, failed uploads,
retention and real rclone copy/read-back on its **local backend**, not an actual
off-site provider. Local CI keys are synthetic/disposable and never owner keys.
