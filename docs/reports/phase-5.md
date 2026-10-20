# Phase 5: branch comparison

## Behaviour and accounting

Reports > Compare branches opens all branches accessible to the signed-in account, independently of the dashboard branch selection. Dates, pinned previous dates, sale cashier and category carry over from Sales. Return to Sales to change these filters. Single-branch accounts see their one branch; zero-activity, previous-only and archived branches stay visible.

Each branch uses its local calendar boundaries. Revenue excludes recorded tax and follows the original fully paid completed sale, including subsequent refunds. Costs and gross profit use the Phase 2 immutable line-cost and verified stock-ledger reversal engine. There is no current-recipe estimate or duplicated financial calculation. Missing historical costs make total COGS/profit/margin unavailable; known subtotals are exported separately. Category means sale-time item category; unknown legacy categories cannot match a selected category. Units include subsequently refunded sales.

Compare revenue, recipe COGS, gross profit, units, gross margin and previous-period growth. Margin changes use percentage points. A zero previous value is new activity or no change, never infinite growth. Revenue ranking uses competition ties and branch ID for stable display. Shares use integer largest remainders to sum to 100%; non-positive total revenue has no rank/share; negative legacy branch revenue makes shares unavailable. Growth is calendar-period growth, not same-store growth or normalised trading-day productivity. Gross profit excludes operating expenses.

Tap any KPI or expanded branch KPI for 50-item paginated sale evidence using the existing profit source endpoint and the same pinned filters. Server permissions enforce reports.view and branch/business scope. Unsynced offline sales are not included. Read-only report work introduces no migration or stock/order transaction changes.

## Files changed

- Backend: SalesReportsController.php (branches report validation/dispatch), ProfitReportService.php (shared metadata and branch-only aggregation), BranchComparisonReportsTest.php.
- Flutter: branch_comparison.dart, branch_comparison_screen.dart, reports_screen.dart, sales_reports_repository.dart; expose existing profit source screen for reuse and fix its Future-returning retry callback.
- Export verification: branch_comparison_test.dart, verify_report_exports.py.
- CI: pos-validation.yml includes branch tests in disposable MySQL report suite.

The branch comparison scans current and previous cohorts in bounded batches, bulk loading line/refund/ledger evidence without per-branch queries or catalogue ranking. Daily materialised summaries and large-range caching remain the later aggregation phase.

## Automated verification

Run backend tests on SQLite memory or a disposable test MySQL database only:

```sh
php artisan test --filter='ProfitReportsTest|ActivityReportsTest|InventoryReportsTest|BranchComparisonReportsTest'
```

Flutter analysis and all unit/widget tests generate CSV/XLSX/PDF fixtures and phone previews. Independent export readers check exact numeric costs and literal formula-like names:

```sh
flutter analyze
flutter test
python tool/verify_report_exports.py
```

## Joint device acceptance: Phases 3, 4 and 5

Use the unmerged PR branch on phone and a disposable backend with its additive Phase 4 migration. Never migrate the main top_coffee_pos database during development.

1. Time/cashier: test a known paid sale, a cancelled order and a refund; confirm local hour/day, cashier attribution, source evidence and previous comparisons. Review prompts require sufficient own/peer samples and are not fraud findings.
2. Inventory: inspect a known ingredient ledger; reconcile opening + movements = closing. Check waste and stock valuation, missing history, low stock, recipe expectations vs gross sale deductions and separate returns. Branch-wide stock and filtered sales usage scopes remain labelled.
3. Branch comparison: compare at least two accessible branches and a quiet branch. Confirm dates, cashiers/categories, local timezones, revenue/growth and missing-cost labels against Profit & performance. Switch dashboard branch and confirm comparison still opens all accessible branches. Restricted accounts must not see another branch.
4. Tap branch revenue/profit to verify order items, timestamps, pagination and retry after an outage. Retry must not display stale page data.
5. Export CSV, Excel and PDF for all three phases; confirm branch names, dates, exact amounts, comparisons, missing-history labels and readable notes. Check 200% phone text.

Keep PR #18 draft/unmerged until joint acceptance completes.
