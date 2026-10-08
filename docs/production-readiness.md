# Production release and recovery

## Before building

Choose the backend host, public HTTPS API URL, permanent Android application ID and release signing key. Keep `android/key.properties`, keystores and all server credentials outside Git. Do not publish a debug-signed app. Changing the application ID after cashier devices contain pending orders creates a different application with different local storage; reconcile those requests first.

`android/key.properties` uses `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Paths are relative to the Android project. Set `POS_APPLICATION_ID` in private Gradle configuration. Release builds deliberately fail if signing is absent or the placeholder application ID remains.

Build with `FLAVOR=prod` and the selected HTTPS `API_BASE_URL` ending in `/api/v1`. `Env.validateProductionUrl` rejects the emulator, localhost, HTTP and credentials embedded in a production URL. Android's main manifest carries the internet permission required by release builds.

## Server configuration

Use PHP 8.2 or a compatible supported version, Composer dependencies from the committed lockfile, and MySQL/MariaDB or PostgreSQL with transactions and row locking. Serve Laravel from `backend-skeleton/public`, never from the repository root. Configure `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL` as HTTPS, a persistent cache, the intended database, and an existing application key. Preserve that key between releases; generating a new key is not a routine deployment step. Do not seed demo accounts in production. Create business, subscription, branches and authorized staff deliberately.

Use `php artisan pos:production-check --json` to inspect environment, debug/key/URL configuration, database type, migration status and KDS cleanup. This command reads configuration/schema only; it does not migrate, seed or change production data. It must return exit code 0 before declaring the server ready. It does not certify HTTPS termination, backups, credentials, printer operation or payment-terminal integration.

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
