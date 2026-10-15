# Production release and recovery

## Subsequent remote preparation

The [deployment/recovery kit](../deploy/README.md) provides Nginx/FPM/systemd
references, encrypted backup/recovery, per-table runtime grants and local health
signals. The [launch register](launch-work-register.md) tracks all ten ranked
actions and the remaining host/operator/privacy/physical-device gates. These
files do not deploy or certify a host. Exact final CI remains in draft PR #11.

## Current candidate status — 15 October 2026

PR #11 remains draft and unmerged. The reviewed baseline `99f4563` passed
backend/MySQL checks, Flutter analysis/tests, native transport checks, Android
builds and emulator workflows. The native printer capture received 312,126
bytes as 180 valid raster bands with one final cut. It used emulator loopback;
it does not certify physical paper output, Khmer readability or drawer motion.

The release-readiness follow-up tightens the read-only HTTPS URL and MySQL
storage-engine checks. Final validation is recorded in PR #11's checks. See
[release-readiness review and handoff](release-readiness-review.md) for verified
fixes, evidence boundaries and the remaining environment/device work.

Production is not ready for cutover: the target host/API URL, permanent signing
identity, target-environment migration/restore evidence, monitoring delivery and
current physical-device acceptance remain pending. These require actual owner
or operator choices and access; no values are inferred from the rehearsal.

## Historical laptop acceptance — candidate f049472

Code candidate `f049472` passed 302 backend tests, 235 Flutter tests, analysis, Android debug build and both GitHub CI jobs. Network printing to the physical XP-N160II was verified through the Android emulator and confirmed on paper. Native offline save/force-stop/session recovery, cashier/branch isolation and one replay passed using a simulated API with no real sales. The local MySQL backup/restore rehearsal compared all 49 tables and 986 rows, passed staging migrations, and confirmed the source was unchanged. The isolated staging database and private backup were retained.

Production hosting is deferred; these local results do not certify a future hosting environment, signing identity or physical cashier device. Do not include real database backups, credentials or signing material in Git. Use `--no-uninstall` for native integration runs intended to preserve application data.

## Before building

Choose the backend host, public HTTPS API URL, permanent Android application ID and release signing key. Keep `android/key.properties`, keystores and all server credentials outside Git. Do not publish a debug-signed app. Changing the application ID after cashier devices contain pending orders creates a different application with different local storage; reconcile those requests first.

`android/key.properties` uses `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Paths are relative to the Android project. Set `POS_APPLICATION_ID` in private Gradle configuration. Release builds deliberately fail if signing is absent or the placeholder application ID remains.

Build with `FLAVOR=prod` and the selected HTTPS `API_BASE_URL` ending in `/api/v1`. `Env.validateProductionUrl` rejects the emulator, localhost, HTTP and credentials embedded in a production URL. Android's main manifest carries the internet permission required by release builds.

## Server configuration

Use PHP 8.2 or a compatible supported version, Composer dependencies from the committed lockfile, and MySQL/MariaDB or PostgreSQL with transactions and row locking. Serve Laravel from `backend-skeleton/public`, never from the repository root. Configure `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL` as HTTPS, a persistent cache, the intended database, and an existing application key. Preserve that key between releases; generating a new key is not a routine deployment step. Do not seed demo accounts in production. Create business, subscription, branches and authorized staff deliberately.

Use `php artisan pos:production-check --json` to inspect environment, debug/key/URL configuration, database type, migration status and KDS cleanup. The URL must be usable HTTPS without embedded credentials, query or fragment; loopback, localhost and the emulator host are rejected. MySQL/MariaDB application databases must use InnoDB for every base table; selecting the driver alone does not prove transactional storage. Views are excluded. This command reads configuration/schema only; it does not migrate, seed, convert tables or change production data. It must return exit code 0 before declaring the server ready. It does not certify DNS, HTTPS termination, backups, credentials, printer operation or payment-terminal integration.

## Database rehearsal

1. Take a consistent backup of the production database and relevant stored assets. Record database version, schema migration head and release commit; verify the backup can actually be restored in an isolated environment.
2. Restore to a staging database with separate credentials. Match the production database engine; SQLite tests do not substitute for a MySQL/PostgreSQL rehearsal.
3. Run the candidate migrations on staging. The kitchen cleanup intentionally deletes KDS-only tables/column and has no reversing `down()` implementation. Preserve backups and do not assume `migrate:rollback` recreates that historical data.
4. Compare order/item/payment/customer/ingredient/stock-movement/table counts and representative totals before/after. Reconcile completed sales and payment amounts, including held orders and completed-order adjustments.
5. Run the eight-phase acceptance checks on staging. Check separate cashier/manager/admin accounts and branch switching.

## Cashier-device rehearsal

Run dine-in hold/edit/save/reopen/pay and takeaway checkout. Verify cash change, split totals, occupied/available table state, cancelled-order history, stock deduction and receipt totals. Test narrow/tablet layouts, light/dark themes, keyboard input and cancellation dialogs.

Warm the catalog while online, then disable the API connection. Submit an order and verify the pending message and retained reference. Force-stop/reopen within the cached-session window; restore the connection and verify exactly one server order/payment/inventory deduction. Switch users/branches before reconnecting and verify another cashier's request is not submitted. Change a price or remove stock while offline; verify the request remains for review without an incorrect completed sale. Simulate insufficient local storage and ensure no new request is sent.

On the actual configured printer, print connection/test, saved cash/split receipts, logo and Khmer sample if used. Check text shaping, paper width, totals, change and cutting. Disconnect the printer and verify an error with a working retry/reprint from order history. A printer failure must never recreate or repay a sale. Verify the E-Receipt share flow on the target OS too.

## Deployment and rollback

Deployment and PR merging require explicit owner approval after the candidate commit, staging results and backup/recovery evidence are reviewable. Stop or drain cashier writes for the approved maintenance window, take a fresh verified backup, deploy the tested candidate/dependencies, run approved migrations, warm Laravel configuration/routes/views, and run the read-only production check. Smoke-test using controlled transactions and reconcile them according to the business's accounting rules. Monitor application/payment/queue failures.

If the release fails, stop new writes, preserve logs and unresolved device queues, and revert application code to the known compatible version. If a destructive migration prevents that version from running, restore the verified database/assets backup through the approved recovery procedure. Reconcile transactions created after the backup before reopening the POS. Never silently delete pending orders to make an error disappear.

References: [Laravel deployment guidance](https://laravel.com/framework/docs/12.x/deployment) and [Flutter offline-first guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first). The checks above are specific to this POS; the references do not certify its deployment.

## System-wide review follow-up (14 October 2026)

See [system-wide engineering review](system-wide-engineering-review.md) for the current candidate, severity-ranked fixes, exact diffs and tests. Earlier acceptance above remains historical evidence for its named commit.

- Set `CACHE_STORE` (the old example's `CACHE_DRIVER` was ignored).
- Configure `SANCTUM_TOKEN_EXPIRATION` to the business-approved positive lifetime in minutes; production readiness rejects an indefinite lifetime. Revocation on password reset/deactivation is automatic.
- The read-only production check now compares cached ingredient stock against the movement ledger. Investigate discrepancies; do not directly edit stock to silence the check.
- Demo seeders refuse production. Continue using deliberate onboarding and private credentials.
- Rehearse the new completion index and receipt-name columns on staging before approved migrations. Historical receipt rows retain their catalog fallback.
- The asset restore helper rejects traversal, links and special files. Continue restoring only into an isolated empty target and verifying database/assets totals before any recovery cutover.
- Kitchen-display removal is preserved at the owner's explicit direction.
- Verify actual production HTTPS, signing, backups, monitoring/alert delivery, physical receipt/scanner/share behavior and offline recovery before release. CI does not certify these environment-specific controls.


## Current improvement batch (15 October 2026)

Production hosting has not been configured. The owner is currently away from the PC/printer; automated validation may continue. This section is a preparation and evidence checklist, not deployment approval or a claim that an environment is ready.

Owner-confirmed historical hardware acceptance on USB Test 120.1 covers manual drawer opening, automatic opening after a completed cash sale, and receipt reprinting without reopening the drawer. That evidence does not certify later checkout changes, the new manual-opening reason dialog, or drawer audit synchronization. The two receipt-choice buttons and the current UI changes still need acceptance when the owner resumes testing.

The shop approved USD accounting with Khmer riel display/shortcuts at US$1 = 4,000 riel. No policy for rounding change or choosing its payout currency has been approved. Do not infer one from equivalent amounts displayed on checkout. Drawer command telemetry records a device-reported attempt/result; it is never proof of mechanical opening and never changes cash balances.

### Hosting and permanent connectivity

- [ ] Record the chosen hosting provider, owner, region, supported PHP/MySQL versions, public HTTPS API URL ending in `/api/v1`, and release commit. No host or credentials have been selected by this review.
- [ ] Serve only Laravel's public directory behind HTTPS; verify certificate renewal, trusted proxy configuration, database access restrictions and persistent storage with the hosting operator.
- [ ] Configure production settings privately, including `APP_ENV=production`, `APP_DEBUG=false`, persistent `CACHE_STORE`, bounded token lifetime and the intended database. Preserve the existing application key and its recovery copy.
- [ ] Verify the intended cashier device can reach the public HTTPS API without USB or the development PC. The current loopback URL and USB reverse connection are development-only.
- [ ] Verify unauthenticated API probes return JSON HTTP 401 with browser, wildcard and JSON Accept headers. A 401 demonstrates a reachable protected endpoint; it does not prove valid login credentials or branch authorization.
- [ ] Run the read-only `pos:production-check --json` against the intended environment and retain the result with the candidate commit. Resolve every failure; do not edit ingredient stock caches directly.

### Release signing and device data

- [ ] The owner chooses the permanent Android application ID and release signing identity, with a private recovery copy of the keystore and its access procedure. Record only non-secret identity/version metadata in release evidence.
- [ ] Build the production flavor against the verified HTTPS API and inspect the signed APK's package identity, version, certificate and network policy. Never distribute a CI USB/debug artifact as production.
- [ ] Plan installation/update without uninstalling an app that contains unresolved orders, operations, print jobs or drawer evidence. A unique CI test application has separate storage; it cannot transfer another app's pending queue automatically.
- [ ] Before cutover, reconcile saved requests under their original cashier/branch and retain a recovery path for any still-unconfirmed payment. Do not clear app data or invent replacement sales to hide a pending state.
- [ ] Resume physical acceptance only when requested: Complete Sale, Complete & Print, cash and split-cash drawer behavior, card/QR-only exclusions, receipt retries/COPY, keyboard/scanner, accessibility and offline recovery. Use controlled rehearsal transactions.

### New drawer-audit migration rehearsal

The additive migration `2026_10_15_000001_create_cash_drawer_events` adds a separate command-evidence table with business, branch, cashier, optional order, reason, result and device/server timestamps. It does not alter orders, payments, shifts, cash movements, ingredients or the stock ledger. Its actor/reference uniqueness supports telemetry retry deduplication.

- [ ] Restore a verified backup to a **fresh isolated copy** matching the intended production MySQL version. Do not reuse the running `top_coffee_pos_pr7_rehearsal_20261013` database or change the port 8001 server for this check.
- [ ] Record schema head, row counts and representative sales/payment/refund/stock totals before migration. Apply the complete candidate migration set only to the isolated copy, then verify original record values and audit history remain unchanged.
- [ ] Verify `cash_drawer_events` columns, required foreign keys, the unique cashier/event-reference index, branch/time index and order/source index. Existing installations should start with an empty new table; historical physical openings are not fabricated.
- [ ] Rehearse the drawer API on the copy: authorized manual reason, same-reference retry, monotonic final result, another branch/cashier rejection and delayed confirmed-cash evidence. Confirm no order/payment/stock/cash-movement records are created by telemetry.
- [ ] Verify upgrade, pre-data rollback and reapplication on the disposable copy. The MySQL release test now covers all five release migrations, including the drawer table, without shifting its populated pre-operations baseline.
- [ ] For the guarded `pos:rehearse-migration` helper, use a newly restored database name matching `top_coffee_pos_pr7_rehearsal_YYYYMMDD_HHMMSS`, separate from the configured source, in local/testing mode. Retain its target and unchanged-original-record report.
- [ ] Once real telemetry exists, do not treat a rollback that drops this table as a routine recovery step. Preserve its audit evidence in the approved backup/recovery process before any schema reversal. Kitchen removal remains the earlier intentional destructive migration.

### Backup and recovery evidence

- [ ] The owner sets recovery-point and recovery-time objectives, backup frequency, retention and responsibility; this review does not invent those business decisions.
- [ ] Back up the consistent database, stored assets and required private configuration/signing recovery material to approved protected storage outside the app host. Keep secrets and real backups out of Git, CI artifacts and chat.
- [ ] Restore into a separate environment and compare database/assets counts and key totals. Include orders, payments, refunds, stock movements, shift/cash movements, audit logs and new drawer evidence.
- [ ] Record the most recent successful backup and measured restore duration. Verify access and recovery instructions with the responsible operator, including transactions created after a backup.

### Monitoring and operating ownership

- [ ] Choose and configure the actual monitoring/logging destination and responsible recipient; no service or recipient is configured by this document.
- [ ] Verify health/uptime and certificate checks, API error/latency alerts, database/cache failures, storage capacity and backup/restore failure alerts. Test delivery to the intended recipient before declaring monitoring ready.
- [ ] Log useful request/operation references while redacting passwords, bearer tokens, signing keys and payment-provider secrets. Do not record card details in diagnostic logs.
- [ ] Agree how staff review unconfirmed orders, saved operations, unresolved print jobs and pending drawer evidence on each device. A server health check cannot see a request that remains only in device storage.
- [ ] Verify alerts and dashboard links lead to an actionable recovery step. Printer uncertainty requires checking paper; payment success must remain distinct from printing or drawer warnings.

The release evidence package should identify the exact candidate commit, CI results, staging migration/restore results, production-check output, signed package metadata and resumed device acceptance. Hosting, signing, backup/monitoring setup and deployment remain pending until verified in the intended environment. No merge, deployment, production migration, running-service change or device test is performed by preparing this checklist.
