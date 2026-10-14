# Daily operations: review and release plan

Prepared 2026-10-14 UTC for PR #7:
https://github.com/sticky268/Top-Coffee-POS/pull/7

This plan authorizes no merge, deployment, production migration or production data change. PR #6 also requires separate explicit merge approval.

## Reviewed code and evidence

Code checkpoint: 2ddf4b8209f71e2106c58dbfab876753e2b6ddf4.
PR #7 targets feature/kitchen-order-updates; that target is not automatically a production release branch.

- POS validation passed: backend suite, separate MySQL operation/concurrency/migration checks, Flutter analysis/tests and Android debug APK.
  https://github.com/sticky268/Top-Coffee-POS/actions/runs/38499077304
- Android integration passed:
  https://github.com/sticky268/Top-Coffee-POS/actions/runs/38499077184
- Owner-PC rehearsal covered shifts, manager review, cash sales, recipe consumption, stock counts, branch availability restoration, consumed refunds and lost-confirmation recovery without duplicate adjustments.
- Layout checks passed at 360x800, 800x1280 and 1280x800. A dashboard branch-selector overflow was fixed and branch switching has a focused regression test.
- Internal database order ID 124 maps to branch receipt number 121. Use database IDs for API routes and branch order numbers for customer-facing references.

## Outstanding before a production release

Physical Android-device testing and confirmation of actual paper receipt/Khmer output remain unverified. The owner chose to pause phone connection troubleshooting. Reported receipt/Khmer results are recorded, but an emulator success message alone cannot validate paper.

Confirm the deployment host, actual production database, approved release branch, backend URL, Android package/signing configuration and devices to update. None may be inferred from the rehearsal setup. The debug APK is a test artifact, not the production distribution package.

The owner must explicitly approve PR #7 merging. PR #6 is separate. A production release needs its own explicit authorization, including any decision to defer outstanding hardware checks.

## Backup preparation, after the production target is identified

1. Record the currently deployed backend commit and app version, and arrange a quiet deployment window.
2. Pause cashier submissions, wait for ongoing requests to finish, and reconcile saved orders and operations on every device. Closing guards currently cover only the device performing the close.
3. Make a consistent full backup of the actual production database, including its schema, rows, migration history and any database objects in use. Confirm the database name; never substitute the rehearsal copy.
4. Back up uploaded assets, the deployed backend/app artifacts, and configuration needed for recovery. Store environment secrets and signing keys securely, outside GitHub and shared test logs.
5. Record backup paths, timestamps, sizes and checksums. Restore the database and assets into an isolated target and verify representative order, payment, refund, stock, loyalty and Khmer records. Keep the original production database untouched.
6. Proceed only after the restore check succeeds. The migration rehearsal against a copied database is useful evidence, but does not replace a fresh verified production backup.

## Merge review

1. Confirm PR #7 still has the expected base and all required checks pass for its final source revision.
2. Review the scope and remaining operating limits below.
3. Obtain explicit owner approval before merging PR #7.
4. Treat PR #6 and movement into the production release branch as separate review/approval decisions. Merging PR #7 into its feature-branch base does not deploy the system.

## Deployment sequence, after explicit release approval

1. Pin the approved backend and app revisions; preserve the previous artifacts and verified backup.
2. Keep cashier writes paused while applying the approved backend release and forward database migrations on the confirmed production connection.
3. Verify API health, migration status, branch/permission boundaries and representative existing financial/stock records.
4. Build and verify the Android release using the approved production API URL, package identity and signing configuration. Keep signing credentials out of source control.
5. Validate deployment through a designated test branch/account or otherwise explicitly approved production rehearsal. Do not copy disposable test fixtures or mutate real sales merely to run the stateful integration tests.
6. Install on one designated device, verify login, branch selection, receipt/Khmer output and recovery, then expand gradually.
7. Reopen cashier access and monitor API failures, unconfirmed device requests, unassigned cash payments and shift differences. Keep the previous release and backup available.

## Recovery

If verification fails before cashier activity resumes, keep writes paused and restore the previous application/backend artifacts and verified database backup as a coordinated recovery.

After any new cashier activity, do not blindly restore an older backup or run migration rollback: that can lose new sales, corrections and stock history. Pause writes, preserve the current database and device journals, reconcile post-release activity, and choose a reviewed forward fix or coordinated restore with explicit owner approval.

CI rollback testing covers pre-adoption rollback, not safe rollback after using the new operation tables.

## Operating limits to communicate to staff

- Opening shifts remains staged adoption; legacy checkout can still create unassigned cash payments.
- Card/QR records do not execute or verify bank transactions. Provider refunds require a separate staff action.
- Transfers represent goods already received, not shipment tracking.
- Recipe availability is an estimate, not a stock reservation.
- Historical unknown costs remain unknown.
- A consumed refund keeps stock unchanged; restock/wastage are restricted to the first full-sale refund.
- Saved requests retain their original user, branch, payload and UUID. Do not create a new request to replace an uncertain one.
