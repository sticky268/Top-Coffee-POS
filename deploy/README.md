# Reference deployment and recovery kit

This prepares a **single-host Linux reference deployment** for the cash-only
pilot. It does not select/purchase a host, register a domain, generate production
credentials, install services, change grants, migrate a database or deploy this
PR. PR #11 remains draft/unmerged. Actual target acceptance and owner deployment
approval are required. See the [launch register](../docs/launch-work-register.md).

## Layout and identities

Nginx terminates HTTPS directly; PHP-FPM runs Laravel; MySQL and Redis listen
locally; systemd runs the scheduler and optional worker. PHP must meet committed
Composer requirements. Adapt the Debian/Ubuntu paths/accounts to the chosen OS.

- `/srv/top-coffee/releases/<commit>/`: root/deployer-owned immutable code.
- `/srv/top-coffee/current`: link to the approved release, outside uploads.
- `/srv/top-coffee/shared/storage`: persistent storage linked into releases.
- Private `.env`/config cache: readable by `posapp` as needed, never public files.
  Preserve `APP_KEY` and its separate recovery copy across releases.
- `posapp`: non-login PHP-FPM/worker identity; can write storage/bootstrap cache,
  not source/deployment files/backups. Grant Nginx read/traverse only to `public/`
  and intended `storage/app/public` assets, never secrets/logs/backups.
- Separate runtime, migrator, backup and recovery DB credentials.
- Backup spool: mode 700, outside the web/app root, inaccessible to `posapp`.
  Use an encrypted local staging volume for temporary plaintext.

`production.env.example` deliberately has empty keys/passwords and a reserved
domain. Fill private values outside Git, set the real HTTPS URL and retain token
lifetime <=720 minutes. Enable cash shifts/manager controls and zero cashier
discount threshold through existing business controls on authorized staging first.
These files do not silently change any existing business policy.

## Server/services

Review Nginx/FPM/systemd files before installation. Only Laravel `public/` is
served and only exact `index.php` executes PHP; hidden files/uploaded PHP paths
are rejected. Access logs omit query strings, bodies, cookies and authorization
headers. Error/application logs still require access/privacy review; never send
credentials in URLs. Web logrotate and Laravel daily logs propose 14 days.

Get a real certificate and test renewal. Run native Nginx/FPM configuration tests
and verify external HTTPS from a cashier device. CI uses a disposable self-signed
loopback fixture to test syntax/file boundaries; it does not verify public TLS or
PHP-FPM. If a proxy/CDN is added, review trusted proxies/client IPs separately.

Keep MySQL, Redis, PHP-FPM and phpMyAdmin closed publicly. Restrict SSH, use keys,
apply supported security updates and test firewall/SSH abuse controls. This does
not change XAMPP or the port 8001 rehearsal server.

Native Flutter needs no browser CORS origins. The explicit CORS config defaults
to no browser origins/no credentialed cookies. Add exact approved HTTPS origins
only for a reviewed staff web client. CORS does not replace bearer authorization.

The scheduler timer runs each minute. Enable the optional queue worker only for
reviewed jobs; checkout/payment/stock transactions must not become blindly retried
jobs. Redis `retry_after` must exceed worker timeout. Restart workers after
approved code/config changes. Verify systemd units and path permissions on staging.

## Runtime grants

`runtime_grants.py` reads target tables and prints SQL. It never creates users,
invents passwords or executes GRANT. From the backend directory:

```sh
python3 tools/runtime_grants.py --credentials /private/operator.cnf --database top_coffee_pos --user pos_runtime --host 127.0.0.1 > /private/runtime-grants.sql
```

An authorized DBA creates a **fresh** local account privately, reviews the SQL,
then applies it with separate admin credentials. Table CRUD is granted except
`SELECT, INSERT` only on `audit_logs` and `SELECT` only on `migrations`.
No broader schema/global/role grants or GRANT OPTION may exist: missing table
privileges do not override broader grants. Re-render/review after schema changes.
Cross-host DB accounts require a separate network/TLS review; this generator
supports loopback only. Runtime credentials must not run migrations.

CI proves normal writes succeed while audit UPDATE/DELETE, migration DELETE,
DDL and system-table reads fail for a disposable runtime account. Actual grants
remain unverified. Administrators can bypass these controls: external immutable
audit retention/checkpoints remain necessary. Runtime gets no backup keys.

## Encrypted backups/recovery

Install a trusted, supported `age` CLI from the selected platform/vendor source.
A recovery operator generates/retains its private identity **outside the app
host**, with a separate secured recovery copy. Only reviewed public recipients
belong on the backup host. Do not upload real identities to Git, CI or chat.
CI keys are disposable synthetic fixtures and are never reused.

After an approved quiet window with all cashier/API/worker writers drained:

```sh
python3 tools/encrypted_backup.py backup --credentials /private/backup.cnf --database top_coffee_pos --assets /srv/top-coffee/shared/storage/app/public --commit APPROVED_COMMIT --writes-drained --recipients /private/recovery-recipients.txt --output /private/backup-spool/snapshot.age
```

Use a unique filename each time. The tool validates both payload checksums,
encrypts manifest/SQL/assets, refuses overwrites and publishes one ciphertext file
atomically. Safe ciphertext hash/size evidence is printed. Keep at least one
tested private recovery identity available independently of the production host.

Private temporary plaintext is removed after success/failure. Unlinking does
not securely erase SSD snapshots/swap/history; staging storage still needs
encryption/access control. `seal` can protect an existing verified legacy bundle
without deleting its original. Never delete the last proven backup.

Copy ciphertext to selected off-site protected/immutable storage and test separate
recovery-account retrieval. No destination or automatic retention deletion is
configured here. Encryption detects modification but does not prove sender
identity: anyone with a public recipient can encrypt another backup. Recover a
trusted retained object/version with independently recorded hash/provenance;
the embedded manifest alone does not authenticate its producer.

On an isolated recovery host, create a new empty database ending in `_restore`,
use separate recovery credentials, and choose a new asset directory:

```sh
python3 tools/encrypted_backup.py restore-rehearsal --credentials /private/recovery.cnf --database top_coffee_pos_restore --assets /private/restored-assets --backup /private/snapshot.age --identity /private/recovery.agekey --work-root /private/recovery-work
```

The entire age stream authenticates before extraction or any DB connection.
Unexpected members/links/duplicates/incomplete manifests are rejected. Default
outer decrypted archive limit: 20 GiB; deliberately raise with
`--max-archive-bytes` if required. Imported SQL is trusted backup content, not
a sandboxed upload. Use a capacity-limited isolated volume and never import
untrusted SQL with production admin credentials.

Restore refuses source/filled-target overwrite and compares rows/data/asset
hashes. Partial SQL restores remain isolated for inspection; do not automatically
retry into them. Measure actual recovery time and reconcile orders, payments,
refunds, shifts, stock, audit/drawer evidence and assets before cutover.

This snapshot helper requires drained writes. Do not schedule its confirmation
flag while trading continues. Proposed RPO 15 minutes cannot be promised by
occasional maintenance backups: continuous binlogs/replica and asset recovery
need design/testing on the chosen host. Device-only unsynced orders are outside
server backups. Off-site storage, scheduling and restore acceptance remain gates.

## Health signals and delivery

`php artisan pos:operations-health --json` is a local read-only command, not a
public endpoint. It reports safe booleans for DB/cache, persistent cache, disk,
recent failed jobs and positive configured login/refund/held-cancellation warning
thresholds. It returns no staff identities, job payloads or exception secrets.
Warnings trigger investigation, never automatic punishment or payment reversal.
`/up` remains liveness only.

The five-minute health timer records failure locally through the alert template.
**Local journaling is not delivered monitoring.** Choose a destination/recipient
and prove delivery for synthetic API/login/backup/stale-backup/disk/certificate
failures. This command cannot see host/network outage, device-only queues or
off-site backup freshness; monitor those externally. Tune thresholds in pilot.

## Release sequence

1. Choose host/domain/operator, permanent signing identity and supported devices.
2. Prove target restore/migration, grants, encrypted off-site retrieval, alert
   delivery and schema-compatible rollback.
3. Confirm cash/manager/shift controls, two-minute OS lock, privacy/cash procedures
   and individual handover. Reconcile device queues before package/storage changes.
4. Record exact commit/signed package and obtain owner merge/deployment approval.
5. Follow the approved quiet-window release, restart workers, run read-only
   production/health checks, validate HTTPS and physical COPY printing, then pilot.
   Never clear app data or reverse financial schema over new sales to hide errors.

Primary references: [age manual](https://github.com/FiloSottile/age/blob/main/doc/age.1.ronn),
[Laravel deployment](https://laravel.com/docs/12.x/deployment),
[MySQL grants](https://dev.mysql.com/doc/refman/8.0/en/grant.html),
[Nginx directives](https://nginx.org/en/docs/http/ngx_http_core_module.html).
