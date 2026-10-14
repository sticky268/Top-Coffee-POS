# Five-business launch and pilot

## Candidate scope

Business records, staff assignments and branch scopes already existed before this release. This candidate expands endpoint isolation coverage and integrity checks for order/shift/stock actors, recipe ingredient branches and payment shift ownership. Foreign IDs remain inaccessible to another business's administrator. Catalog photos on public storage remain public assets; no confidential file-delivery claim is made.

New per-business controls require an open cashier shift for cash payments, including split cash. Server checks preserve the saved original shift; a queued payment never silently moves to a later shift. Card/QR remain cashier-recorded payments, not provider-verified transactions. Held orders may be saved without payment; their cash payment requires the shift.

Manager/admin sign-in approves refunds, additional charges and discounts **above 10%** of subtotal. The percentage is configurable from 0 to 100. Cashiers can apply smaller discounts. Approval records identify the manager through the signed-in actor, with amount and reason for refunds. This is a manager-performed workflow, not a second-person approval or a password/PIN override inside another cashier's session. Managers need their own account and their own shift for cash. Do not share owner credentials.

A rejected checkout leaves its outbox request available for reconciliation. Correct a discount in the cart or have a manager recreate the transaction after checking that the original request was rejected; do not replay another cashier's saved UUID under a different account. Preserve attempted offline cash lacking a shift for manual reconciliation. Never delete pending requests merely to hide a problem. New cash requests with no saved shift are blocked before queueing when the client knows the policy; the server remains authoritative.

Existing installations retain disabled controls through migration to avoid changing unresolved historical cash. Stop cashier writes, reconcile device queues, initialize the reviewed manager permissions and enable controls for every active business before launch. No old order/payment totals are rewritten. The read-only production check fails while any active business's controls are disabled.

## Server preparation

Hosting account, region, domain and access are still needed. No server has been purchased or deployed. Use the existing `docs/production-readiness.md` checklist for HTTPS, production configuration, application key, migrations and signed Android distribution. Serve only `backend-skeleton/public`; bind the database privately. Keep development/demo databases and credentials off production. Set `APP_DEBUG=false`; store the application key privately and preserve it across releases and restores.

Before a live change, restore a backup into separate staging credentials, migrate it, and run the tenancy and production checks. Deployment must reference the tested commit. Do not use `migrate:fresh`, the integration fixture seeder or a demo seeder against a business database. Fresh production installations may initialize `RolePermissionSeeder` only; existing installations must review its global role changes before running it (it synchronizes permission grants). Managers now receive `orders.create` so they can perform approved checkouts.

New independent business setup, from the backend directory:

```bash
php artisan pos:onboard-business "Business name" --owner="Owner name" --email="owner@example.com" --branch="Main" --timezone="Asia/Phnom_Penh"
```

The command prompts for a hidden password twice, creates a separate business/branch/owner in one transaction, starts a 30-day trial, enables both controls and writes an onboarding audit entry. It creates no catalog, sales or shared staff. Review the subscription/plan before trial expiry; this command does not set up billing. The owner signs in, adds only their staff, products/recipes and printer settings. Repeat once per independent business; branches represent locations within that business, not unrelated customers.

For an existing business after reconciliation:

```bash
php artisan pos:checkout-controls BUSINESS_ID
php artisan pos:checkout-controls BUSINESS_ID --enable --discount-percent=10
php artisan pos:tenancy-check --json
php artisan pos:production-check --json
```

The first command is inspection-only; the second changes policy and audits it. Refresh/sign in again on cashier devices to load the policy. Review cash float and open the shift through Daily Operations before cash checkout. An old cached client cannot bypass server enforcement.

## Backup and restore evidence

`backend-skeleton/tools/mysql_backup.py` uses Python 3 plus native `mysql`, `mysqldump` and `tar`. It saves a compressed database, public upload assets, release commit, server version, table counts, deterministic data hashes, asset hashes and archive checksums. Credentials are read from an external MySQL client option file; passwords do not go in command arguments. On Unix the option file must be mode 600. Set its `default-character-set=utf8mb4`. Use a separate backup database account with the required dump permissions and a separate restore account restricted to staging. Private backups must stay outside Git and web-served directories.

During a maintenance window drain writes (including queued clients) before using:

```bash
python3 tools/mysql_backup.py --credentials /private/mysql-backup.cnf backup --database pos_live --assets storage/app/public --output /private/backups --commit TESTED_COMMIT --writes-drained
```

Provision a separate empty staging database whose name ends in `_restore`; select it explicitly:

```bash
python3 tools/mysql_backup.py --credentials /private/mysql-staging.cnf restore-rehearsal --database pos_staging_restore --assets /private/restored-assets --backup /private/backups/BUNDLE_DIRECTORY
```

The tool refuses the source database and populated targets. It verifies archive checksums, restored table contents/counts and every regular uploaded file. Asset symlinks are unsupported. Partial restore results are kept for inspection. Restore only bundles you created and trust. The manifest hashes detect accidental corruption, not malicious replacement; backups need protected storage and encryption outside this tool. Database data hashing sorts INSERT rows in memory, so large future databases may need a streaming implementation.

After restore, point a separate staging app at the restored database/assets; preserve the matching application key privately, migrate, run `pos:tenancy-check`, then perform cashier acceptance. Do not claim disaster recovery complete from archive creation alone. CI exercises a disposable MySQL restore with Khmer text, decimals and asset contents, plus overwrite refusal; it does not certify a future hosting backup or production data.

Start with a daily closed-business backup, keep seven daily and four weekly copies, and copy them to private encrypted storage outside the server. A server disk copy alone does not survive server loss. Decide the acceptable lost-sales window with the first business; daily backups can lose a day's writes. Take a new verified backup before every release. Restore a copy monthly and after schema changes. Scheduling, off-server credentials, retention deletion, TLS and monitoring must be configured on the actual host once selected; none are installed remotely by this PR.

## One-business pilot

Use a separate rehearsal business first: two businesses with different owners, each owner's cashier/manager, and two branches in one business. Verify own lists/reports and blocked foreign IDs; sales, cash/split payments, held-order pay, stock deductions, refunds, discount approval, shift close, offline restart/replay and actual paper print/COPY/retry. Confirm a cashier can't grant themselves a manager role. Check Khmer and phone/tablet layouts on the intended devices. Verify real QR/card payments separately; marking them paid in the POS does not verify a bank transaction.

Then onboard one real business with clean opening inventory/cash and its own staff. Agree a daily close review and a contact for failures. Review unassigned cash, drawer differences, unresolved outbox operations, failed/uncertain prints, refunds/discount audits, backup age and restore evidence every day. Pause expansion on duplicate sales, cross-business access, incorrect stock/cash totals or failed recovery. Reconcile before reopening.

After at least a full operating week with reconciled closes and a successful host restore rehearsal, onboard the other four individually. Keep each owner's data and subscription separate. A pilot requires the businesses, target hardware and host; code and CI alone cannot complete it.
