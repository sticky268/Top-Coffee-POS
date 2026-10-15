# Production preparation and operator runbook

**Prepared for draft PR #11. Nothing here authorizes merge, deployment or live-server access.**
The target below is an assumption: a dedicated Ubuntu 24.04 LTS VPS, PHP 8.3 FPM,
MySQL 8/InnoDB, Redis, Nginx terminating TLS directly, no public phpMyAdmin, and a
separate monitoring/recovery machine. XAMPP remains local development only.
Adapt service names and retest on the chosen staging host if this changes.

Manager-PIN enforcement is now implemented; see
[manager-pin-approval.md](manager-pin-approval.md). The read-only business check
requires migrated PIN fields, actual route enforcement and an enrolled,
unlocked authorized manager for every active branch. It still fails on
unconfigured staging/production data. Enroll real managers privately through
Settings using their own password; never manufacture hashes or disable the gate.

## Host, identity and TLS

An owner must purchase the VPS/domain, name the operator and recovery deputy,
choose the region/provider, approve retention/privacy policies and authorize a
staged pilot. Keep a provider console open and test an independent SSH session
before changing access. Use a named sudo operator and SSH keys, disable root and
password SSH only after that test, and apply OS security updates. Schedule and
test reboots; an unattended reboot during trading needs an explicit plan.

On an approved staging host only:

```sh
sudo apt-get update
sudo apt-get install nginx php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath mysql-server redis-server python3 age rclone ufw fail2ban
```

The first command refreshes package metadata; the second installs the runtime and
operational tools. Install Composer from its verified official distribution;
build with the committed lock, `composer install --no-dev --prefer-dist
--optimize-autoloader --no-interaction`. This installs reviewed dependencies;
it must not run `composer update` on the server. Verify `composer audit --locked`
in CI and the release build environment.

Create `posapp` as an unprivileged no-login account. Code/releases and `/opt/top-coffee-ops`
are root/deployment-owned and not writable by posapp; only shared storage and each
release's `bootstrap/cache` are writable by posapp. Keep `/etc/top-coffee` private,
with MySQL client files, `.env`, rclone config and alert secrets mode 600 and the
appropriate single service owner. Never put these in Git, web root, ticket or log.

Prepare `/srv/top-coffee/releases/<exact-commit>/backend-skeleton`, a shared
`/srv/top-coffee/shared/.env` and shared `storage/`; each release links `.env` and
`storage` to these exact shared paths. Keep current/previous as symlinks to real,
immutable SHA-named release directories. Bootstrap the first **staging** current
symlink manually while access remains restricted; the script handles subsequent
activation. Do not expose a bootstrap build whose readiness gates fail.

Copy `deploy/production.env.example` privately to the shared `.env`; replace the
reserved domain and supply actual values through the owner's secret store.
`APP_DEBUG=false`, `APP_ENV=production`, cash-only payment methods, token expiry
720 minutes and Redis are required. Generate APP_KEY **once for a new installation**
with `php artisan key:generate`; it creates Laravel's encryption key. Save an
independent recovery copy. Never regenerate an existing key to fix an error.
Generate a separate >=32-character random `POS_HEALTH_TOKEN` privately (e.g. a
password manager); it is not a staff token. Blank disables protected health.
Native tablets need no permissive CORS origins.

Edit `deploy/nginx.conf.example` with the actual domain and certificate paths,
then install it in the Nginx http context. Its web root is **public/**, only
index.php executes, hidden paths and uploaded PHP are blocked, TLS redirects use
a fixed hostname, and access logs exclude query/auth/body/cookie values. CSP is
for this API host, not a separately hosted browser UI. HSTS applies only after
valid HTTPS; do not add includeSubDomains without owning every subdomain's TLS.
Obtain a real publicly trusted certificate with the provider's ACME workflow,
prove renewal on staging and monitor expiration independently. Do not turn off
TLS verification or point public Nginx at the repository root.

```sh
sudo nginx -t
sudo php-fpm8.3 -t
```

These validate configuration without reloading the services. Install the FPM pool
from `deploy/php-fpm-pool.conf.example`, remove unused/default pools, and install
`deploy/php-fpm-systemd.conf.example` as the documented drop-in. SIGQUIT/mixed
allows the FPM master to drain requests before termination. Bound web requests at
60 seconds and allow 120 seconds for stopping; force-killed work can roll back,
so verify no writers remain before a backup. A dedicated PHP service is assumed;
do not pause unrelated sites on shared hosting. Run `systemctl daemon-reload`
after reviewing unit edits; it rereads unit definitions without starting them.

## Firewall and fail2ban

Set `ADMIN_IP` privately to the operator's current public IP in the approved host
shell (no value is supplied here). Retain provider-console recovery and a second
SSH connection. These commands change firewall rules and must be run by the owner:

```sh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from "$ADMIN_IP" to any port 22 proto tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

In order: deny unsolicited inbound traffic, permit outbound package/backup/alert
connections, allow only the chosen administrator IP to SSH, allow ACME/redirect
HTTP and HTTPS, activate the firewall, then inspect the result. Refuse to run if
ADMIN_IP is unset. Apply equivalent provider firewall rules and verify IPv6 too.
Never open 3306, 6379, FPM, phpMyAdmin or the Laravel development server. Bind MySQL
and Redis to loopback/private interfaces; use a Unix FPM socket. If Docker is
introduced, separately verify published ports against the provider firewall.

Install `deploy/fail2ban/top-coffee.local` in `/etc/fail2ban/jail.d/`:

```sh
sudo fail2ban-client -t
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

These validate the jail, activate its SSH protection and inspect the loaded jail.
Test bans from a disposable secondary source, preserving owner-console access.
Laravel handles POS login throttling; do not ban a shop's shared NAT on every 401.

## MySQL grants: separate operator, migrator, backup and runtime identities

Use a fresh `pos_runtime@localhost` account with a real generated password,
created privately by the DB administrator. No passwordless root, remote root,
GRANT OPTION, schema-wide privileges or publicly reachable phpMyAdmin. Review
`SHOW GRANTS` before use; table grants cannot cancel existing broad grants.
Migration credentials are not the application's credentials. Backup credentials
need reviewed dump/read privileges, not DDL; recovery CREATE/DROP belongs only
on an isolated recovery-host MySQL instance.

From backend-skeleton on an approved **staging** database:

```sh
python3 tools/runtime_grants.py --credentials /etc/top-coffee/operator-client.cnf --database top_coffee_pos --user pos_runtime --host localhost > /etc/top-coffee/reviewed-grants.sql
mysql --defaults-extra-file=/etc/top-coffee/operator-client.cnf < /etc/top-coffee/reviewed-grants.sql
```

The first command only generates table-level SQL from the migrated schema. Review
it privately before the second command applies it. Protect the SQL mode 600.
Audit tables get SELECT/INSERT, migrations SELECT, normal tables CRUD. Rerun and
review after migrations add tables, using the separate operator account. Never
run migrations as runtime. `tools/test_runtime_grants.sh` applies this generator
to a disposable CI account and proves CRUD works while DROP (table/schema), ALTER,
TRUNCATE, audit UPDATE/DELETE, migrations writes and mysql.user reads fail. Its
CI guards deliberately prevent use as a production script.

## Backup, off-site recovery and retention

See [backup-and-recovery.md](backup-and-recovery.md) for exact commands, key custody,
closed-shop drain, failure behavior, scratch restore and proposed retention.
Use a separate provider/account for off-site copies with server-side immutability
and scoped upload/read permission, no delete permission. Encryption alone does
not protect availability if the same account can erase both copies.

## Actual alerts and protected health

`GET /api/v1/operations/health` accepts only a separate monitor bearer secret,
returns safe booleans with no-store, 200 healthy or 503 unhealthy, and rejects
missing/unconfigured/wrong secrets. `/up` is Laravel liveness only. Checks cover
DB, cache, disk, failed jobs and audit event thresholds. Failed-login spikes count
persisted known-account audit events; arbitrary unknown-email attempts need
provider/reverse-proxy metrics in addition to this signal.

Install an exact reviewed checkout, root-owned and not writable by the app, at
`/opt/top-coffee-ops/`. Service templates invoke scripts in its deploy/ directory;
the backup script uses the sibling backend-skeleton/tools in that same checkout.
Create `alerts.json` from the blank example outside Git with a real bot token and
numeric chat ID chosen by the owner; no credentials are invented. Restrict bot
membership/recipient access and rotate via provider on compromise.

```sh
python3 deploy/alerts.py test --config /etc/top-coffee/alerts.json
```

This **sends a real Telegram message** to the configured recipient. The owner must
run it and acknowledge receipt before enabling timers. A successful HTTP status
without Telegram `ok:true`/message ID is a failure. Test code uses only synthetic
transport fixtures and does not contact Telegram.

Install watch.py and its timer on a separate always-on host; an alert job on a
dead VPS cannot report its own outage. Create no-login `posmonitor`, its private
mode-700 `/var/lib/top-coffee-monitor`, and mode-600 monitor/alert files owned by
that service user. Its monitor config holds the real HTTPS URL and dedicated
health token. Python's TLS verification stays enabled and redirects are refused.

```sh
python3 deploy/watch.py --config /etc/top-coffee/monitor.json
```

This probes HTTPS and sends fixed health/login-spike alerts, with a persisted
15-minute cooldown only after provider acknowledgement. A failed send is retried
next invocation. The external timer runs every minute; use an independent
provider check for failure of the monitor itself. Local `top-coffee-health.timer`
is optional secondary telemetry. `top-coffee-alert@health_failed.service` now
actually delivers; it no longer just writes a local logger line. Backup failures
use `backup_failed`. Monitor planned closed-window downtime explicitly rather
than silently suppressing unlimited outages. Track backup age externally and
page the named operator if no verified receipt appears within 26 hours; the
current job reports failures, not a timer that never fired. Do not claim the
missing independent dead-man/freshness monitor is implemented by these scripts.

## Staged activation and rollback

The release script targets Ubuntu's `php8.3-fpm.service`. Prepared dependencies,
private shared config/storage, exact source SHA, a <=24h off-site-verified backup
receipt matching current code, closed-shop write drain and schema compatibility
are mandatory. It never pulls code, installs packages, migrates, restores a DB,
changes firewall or grants, or sends a release automatically. Review and test
schema migrations separately on a restored copy before any approval.

```sh
python3 deploy/release.py deploy --root /srv/top-coffee --release "$REVIEWED_SHA"
```

With REVIEWED_SHA set to a real reviewed 40-character commit, this validates the
prepared layout and prints a plan only. No services or symlinks change.

```sh
sudo python3 deploy/release.py deploy --root /srv/top-coffee --release "$REVIEWED_SHA" --backup-receipt "$VERIFIED_RECEIPT" --writes-drained --schema-compatible --execute
```

Only the authorized operator later runs this. It validates backup evidence and
both production/business gates, stops scheduler/queue, enters shared maintenance,
switches current atomically, reloads FPM, checks health, resumes and records
previous. Gate failure (including missing manager enrollment) occurs before maintenance. A
post-switch failure attempts code rollback and resumes old code; restart failures
remain errors requiring inspection. OS kill/power loss cannot be handled by
finally: inspect current/previous, maintenance state and services via provider
console before reopening. Do not infer a failed command left everything running.
No write transaction may be in flight at activation; attestations require real
operator checks and all nonstandard writers stopped.

```sh
sudo python3 deploy/release.py rollback --root /srv/top-coffee --backup-receipt "$VERIFIED_RECEIPT" --writes-drained --schema-compatible --execute
```

This activates recorded previous through the same gates, recording the outgoing
release as previous. Obtain a fresh matching backup receipt for the **current**
release before rollback. **Code rollback is valid only for compatible schemas.**
Never reverse financial migrations or restore over a trading database. For data
loss, isolate writes, restore to a new instance and reconcile payments, ledger,
assets and device queues under the incident procedure. External HTTPS and tablet
smoke checks are still required after a successful activation.

## Required checks and evidence

Run from backend-skeleton: `php artisan test` executes the Laravel suite;
`composer audit --locked` checks locked dependencies. From frontend:
`flutter test` executes Flutter tests. At repo root:
`python3 -m unittest discover -s deploy/tests -p 'test_*.py'` checks operational
failure paths; `python3 deploy/check_signing_files.py` rejects tracked signing
keys; `bash -n backend-skeleton/tools/test_runtime_grants.sh` parses the grants
proof script without applying anything. CI also tests the actual generator on
MySQL, encrypted dump/restore and real rclone local-backend copy/read-back.

CI/synthetic service tests are not evidence of real VPS, external notification,
off-site account, public certificate, permanent signed package or physical printer
acceptance. Record those in [pre-pilot-checklist.md](pre-pilot-checklist.md).

Primary references: [Laravel deployment](https://laravel.com/docs/12.x/deployment),
[Ubuntu firewall](https://ubuntu.com/server/docs/firewalls/),
[fail2ban jail settings](https://manpages.ubuntu.com/manpages/noble/man5/jail.conf.5.html),
[Telegram Bot API](https://core.telegram.org/bots/api),
[rclone immutable copy](https://rclone.org/commands/rclone_copy/).
