# System-wide engineering review — 14 October 2026

## Scope and owner decisions

This pass reviews the GitHub candidate on `codex/checkout-ui-polish`, following the [checkout review](pos-checkout-engineering-review.md). Active server code is `backend-skeleton`. Exact changes for this pass: [compare the checkout review baseline to the current candidate](https://github.com/sticky268/Top-Coffee-POS/compare/c631a8898a108bc7c09d44529be2a5cb58763edd...codex/checkout-ui-polish). Each linked commit contains the actual fixes and regression tests.

The owner explicitly chose to **preserve the earlier kitchen-display removal**. KDS restoration is excluded despite the older generic checklist. PR #11 remains draft and unmerged. No deployment, production database access, credential provisioning or payment-provider setup is included.

The user's uncommitted local presentation edits are absent from GitHub. They were not overwritten or treated as reviewed code. The local checkout, generated Flutter plugin files, main database, rehearsal database and backend on port 8001 were untouched. Historical device/backup evidence in production-readiness.md belongs to its stated older candidate; it is not evidence for new code.

## Verified findings and fixes

No Critical finding was confirmed in this reviewed remote scope. Severity describes the original defect, not the residual risk after the fix.

| Severity | Finding and consequence | Fixed behavior and regression evidence |
|---|---|---|
| High | Resetting a password or deactivating/deleting staff left existing API tokens usable. | Revoke tokens with the account change; UserTest covers reset and deactivation. |
| High | A branch manager could modify globally shared staff credentials despite assignments outside their control. | Management requires all target assignments to be within the manager's branches; UserTest covers shared staff denial. |
| High | Audit views exposed other branches' activity to restricted staff. | Filter by trusted auditable branch; legacy unscoped rows are limited to the actor. AuditLogApiTest covers isolation. |
| High | Concurrent branch creation could exceed the subscription limit. | Lock the business row and recheck the current count in the transaction; real MySQL contention test expects one creation and one rejection. |
| High | Subprecision stock/recipe/purchase quantities could disagree with stored decimal quantities. | Validate quantity to 3 decimals and cost to 4; normalize ledger/cache changes together. SystemIntegrityReviewTest verifies rejection without writes and cache/ledger agreement. |
| High | A lost purchase response followed by retry could duplicate the purchase and stock. | Persist the request before sending, retain its UUID across restart, and transactionally replay the original result. Changed reference details return 409. Server and client restart tests cover this. Legacy callers without UUID retain compatibility and cannot receive retry guarantees. |
| High | Late login/restore completion could revive a logged-out session or replace newer credentials. | Session revisions, serialized credential writes and captured logout authorization prevent stale mutations. Auth controller/repository tests cover logout races. |
| High | Asset restore accepted archive traversal or links outside the target. | Validate every member before extraction; reject unsafe paths, links and special files. Python tests cover normal restore, traversal and symlinks. |
| Medium | Invalid branch timezones and server-local date windows misclassified completed sales. | Validate IANA timezones; use branch-local calendar boundaries converted to UTC and completion timestamps. DST hour windows follow elapsed UTC hours. ReportsTest covers cross-date completion. |
| Medium | Reports omitted additional charges/refunds and presented payment collection totals without reconciliation. | Show base sales, supplemental charges, refunds and net sales; payment collections subtract recorded refunds. Tests cover 10 + 2 - 3 = 9. The screen/export explicitly distinguishes completed-order cohorts from Operations' adjustment-event dates. |
| Medium | Daily charts issued queries per date, completion filters wrapped indexed columns, and dashboard item counts required additional queries. | Aggregate chart buckets, bounded date range, indexed completion range and database item sums. ReportsTest checks chart query growth; additive completion index migration included. |
| Medium | Old branch/filter responses could overwrite newer client data. | Generation checks in the changed list/detail/summary controllers discard obsolete responses; branch-race regression verifies orders. This is not a claim that every asynchronous path in the application has a dedicated race test. |
| Medium | A quickly failing parallel catalog request could escape the intended error handler. | Await both requests together with Future.wait; failure regression verifies error state. |
| Medium | Printing a failed queue item could appear successful. | Receipt/bill actions throw on failed final print status; a failed connection test verifies error propagation without creating another sale. |
| Medium | Catalog renames changed names on historical receipt reprints. | Snapshot product/variant names at checkout. Legacy rows use the current catalog fallback; historical names are not invented. Rename/reprint API test included. |
| Medium | Report export actions were missing. | Implement actual CSV, XLSX and PDF generation/sharing using report data, metadata and financial adjustments. Tests parse ZIP/XML and CSV; independent openpyxl and pypdf checks open the generated files. Strings remain literals in Excel and formula-leading CSV fields are escaped. |
| Medium | Continuous background sync failures caused repeated attempts without backoff. | Bounded exponential delay measured by Stopwatch avoids wall-clock drift; manual retry remains available. OrderSync tests verify suppression and manual retry. |
| Medium | Readiness accepted indefinite token lifetime; demo seeders could run in production; caught checkout failures lacked central reporting. | Honor SANCTUM_TOKEN_EXPIRATION, require a bounded lifetime in readiness, refuse production demo seeding and report caught checkout failures. ProductionCheckTest covers seed refusal. Actual external alert delivery is an environment check. |
| Medium | Readiness did not detect cached inventory drift. | Read-only ledger/cache comparison fails readiness on drift, without changing stock. SystemIntegrityReviewTest verifies detection without repair. |
| Medium | Customer detail loaded unbounded order history; history pagination was not bounded. | Limit embedded orders to 20 and validate history pagination; use the existing paginated endpoints for older records. |
| Medium | Staff account mutations lacked transactional sanitized audit entries. | Record creation/update/deletion without passwords or tokens in the same transaction. |
| Low | SKU search did not support the keyboard scanner workflow; product images decoded at unbounded resolution. | Search SKU, submit an exact unique SKU using Enter, preserve variant selection, clear/refocus after submit, use 48px search target and bounded image decoding. SKU/widget tests included. Physical scanner behavior still needs device acceptance. |
| Low | Example cache variable did not match Laravel's configured variable; production URL validation accepted the wrong API path/query/fragment. | Use CACHE_STORE and enforce an HTTPS API URL ending in /api/v1 with no credentials, query or fragment. Env tests cover invalid URLs. |

The earlier checkout review separately fixes cent rounding, discount bounds, distinct offline sale references, atomic payment/loyalty/audit effects, table occupancy, MySQL order-number concurrency, held-payment retry matching and confirmed outbox monotonicity. These protections remain in the candidate.

## Checklist coverage and boundaries

1. **Correctness:** money/discount/payment regressions, stock precision, session/request races, branch calendar windows, receipt snapshots and printer error propagation.
2. **Integrity:** retained transactional order/payment/inventory path, ledger-only stock writes, replay protection, subscription race lock, ledger reconciliation and additive migrations. No direct stock-edit UI was introduced.
3. **Security:** reviewed authenticated/subscription-protected route inventory, role/branch/business scoping, request validation, existing login throttle and secure device storage; fixed verified token/staff/audit gaps. No external payment credentials or pretend integration added.
4. **Performance:** aggregate charts, bounded reporting/pagination, completion index, dashboard item sum and bounded image decode. This is code/query regression evidence, not production-scale latency certification.
5. **UX:** remote checkout/presentation baseline retained; SKU/Enter flow, explicit export busy/error states, responsive existing report layout and honest printer failure. Local uncommitted UI remains outside this pass.
6. **Offline/sync:** prior durable order/outbox controls retained; bounded background retries, stale-session guards and durable purchase requests reuse the existing isolated Operations queue. Price/stock conflicts continue to require review; no queue is silently discarded.
7. **Quality:** existing repositories/controllers/services remain the boundaries; no second export backend, fake payment service or invented tax rule. Changes target observed failure modes rather than broad architectural replacement.
8. **Receipts/reports:** CSV/Excel/PDF, report reconciliation, branch timezones, print failure and historical item-name stability. Business tax configuration was not supplied; existing behavior is preserved rather than inventing a rate.
9. **Tests:** backend feature tests, real MySQL contention, Flutter controller/widget/repository tests, native integration, independent export readers and backup archive tests. Consult PR checks for the final candidate result.
10. **Production:** release guards and checklist retained; bounded token/ledger checks, seed protection and hardened archive restore added. Hosting, real credentials, alert routing, signing, fresh backup restore and physical device acceptance cannot be certified by repository CI.

## How to verify

CI runs the full backend PHPUnit suite and Python archive tests, Flutter analysis/tests, independent XLSX/PDF readers and a debug Android build. The MySQL job runs operation tests, real row-lock contention and populated migration checks, checkout/business isolation, and a private backup/isolated restore. The separate native integration workflow exercises Daily Operations on an Android emulator.

For targeted checks, use SystemIntegrityReviewTest, UserTest, AuditLogApiTest, ReportsTest, ProductionCheckTest and OperationsConcurrencyTest; client auth, order sync, orders list, receipt action, SKU search, operations repository and report exporter tests. Exact test code is included in the compare link.

Two new migrations are additive: orders(branch_id,status,completed_at) and nullable order item name snapshots. Rehearse both on a restored staging database before an approved deployment. Existing KDS cleanup is intentionally destructive and is not undone.

On the cashier device verify real printer failure/retry, paper width/cutting and any Khmer shaping, scanner Enter/variants, tablet/narrow layout, large text, theme contrast, share sheets, offline force-stop/restart and user/branch switching with pending requests. These are acceptance checks, not unfinished hidden code changes. Keep the production deployment and merge pending explicit owner approval.

## Files changed in this pass

- `.github/workflows/pos-validation.yml`
- `backend-skeleton/.env.example`
- `backend-skeleton/app/Console/Commands/ProductionCheck.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/AuditLogController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/Auth/AuthController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/BranchController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/CustomerController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/DashboardController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/IngredientController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/OrderController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/PurchaseController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/RecipeController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/ReportsController.php`
- `backend-skeleton/app/Http/Controllers/Api/V1/UserController.php`
- `backend-skeleton/app/Models/Order.php`
- `backend-skeleton/app/Models/OrderItem.php`
- `backend-skeleton/app/Services/AuditLogService.php`
- `backend-skeleton/app/Services/StockMovementService.php`
- `backend-skeleton/config/sanctum.php`
- `backend-skeleton/database/migrations/2026_10_14_000001_index_completed_sales.php`
- `backend-skeleton/database/migrations/2026_10_14_000002_snapshot_receipt_item_names.php`
- `backend-skeleton/database/seeders/DatabaseSeeder.php`
- `backend-skeleton/database/seeders/UserSeeder.php`
- `backend-skeleton/tests/Feature/AuditLogApiTest.php`
- `backend-skeleton/tests/Feature/OperationsConcurrencyTest.php`
- `backend-skeleton/tests/Feature/OperationsMigrationRehearsalTest.php`
- `backend-skeleton/tests/Feature/ProductionCheckTest.php`
- `backend-skeleton/tests/Feature/ReportsTest.php`
- `backend-skeleton/tests/Feature/SystemIntegrityReviewTest.php`
- `backend-skeleton/tests/Feature/UserTest.php`
- `backend-skeleton/tools/mysql_backup.py`
- `backend-skeleton/tools/test_backup_archive.py`
- `frontend/android/app/build.gradle.kts`
- `frontend/lib/core/config/env.dart`
- `frontend/lib/core/network/api_client.dart`
- `frontend/lib/core/offline/order_sync.dart`
- `frontend/lib/core/receipt/receipt_action_service.dart`
- `frontend/lib/features/audit_log/application/audit_log_list_controller.dart`
- `frontend/lib/features/auth/application/auth_controller.dart`
- `frontend/lib/features/auth/data/auth_repository.dart`
- `frontend/lib/features/branches/application/branch_list_controller.dart`
- `frontend/lib/features/customers/application/customer_orders_controller.dart`
- `frontend/lib/features/customers/application/customers_list_controller.dart`
- `frontend/lib/features/expenses/application/expense_categories_controller.dart`
- `frontend/lib/features/expenses/application/expense_summary_controller.dart`
- `frontend/lib/features/expenses/application/expenses_list_controller.dart`
- `frontend/lib/features/orders/application/order_detail_controller.dart`
- `frontend/lib/features/orders/application/orders_list_controller.dart`
- `frontend/lib/features/pos/application/pos_catalog_state.dart`
- `frontend/lib/features/pos/presentation/pos_screen.dart`
- `frontend/lib/features/pos/presentation/widgets/product_card.dart`
- `frontend/lib/features/pos/presentation/widgets/product_search_field.dart`
- `frontend/lib/features/products/application/products_controller.dart`
- `frontend/lib/features/purchasing/application/purchase_creation_controller.dart`
- `frontend/lib/features/purchasing/application/supplier_list_controller.dart`
- `frontend/lib/features/purchasing/data/purchase_repository.dart`
- `frontend/lib/features/reports/application/reports_controller.dart`
- `frontend/lib/features/reports/data/report_exporter.dart`
- `frontend/lib/features/reports/domain/reports_models.dart`
- `frontend/lib/features/reports/presentation/report_export_actions.dart`
- `frontend/lib/features/reports/presentation/reports_screen.dart`
- `frontend/lib/features/staff/application/staff_list_controller.dart`
- `frontend/lib/features/subscription/application/subscription_controller.dart`
- `frontend/pubspec.yaml`
- `frontend/pubspec.lock`
- `frontend/test/core/config/env_test.dart`
- `frontend/test/core/offline/order_sync_test.dart`
- `frontend/test/core/receipt/receipt_action_failure_test.dart`
- `frontend/test/features/auth/auth_controller_test.dart`
- `frontend/test/features/auth/auth_repository_test.dart`
- `frontend/test/features/operations/operations_repository_test.dart`
- `frontend/test/features/orders/orders_list_controller_test.dart`
- `frontend/test/features/pos/sku_search_test.dart`
- `frontend/test/features/products/products_controller_test.dart`
- `frontend/test/features/reports/report_exporter_test.dart`
- `frontend/tool/verify_report_exports.py`

This document and the production-readiness update accompany those implementation changes. Full patches, not replacement snippets, are committed to PR #11.
