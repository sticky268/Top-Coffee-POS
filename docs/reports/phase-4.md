# Phase 4 - inventory reports (combined review with Phase 3)

Open Reports, select dates and branches, and choose **Inventory report**.
The selected current/comparison calendar dates are pinned from the sales report.
Both phases stay on the same unmerged review branch, codex/reports-time-cashier.

## Definitions and limits

- Stock quantities come only from signed stock_movements, never current_stock or
  balance_after. Opening is before local midnight on the first date; closing is
  before local midnight after the last date. Every branch uses its own timezone.
- Historical valuation sums signed ledger quantity times recorded historical unit
  cost. Unknown movement cost makes valuation unknown until stock is exhausted.
  Negative ledger balances require review. Cost-only edits outside the ledger do
  not revalue historical inventory. This is ledger valuation, not current prices.
- Waste is negative wastage movement quantity and recorded movement cost in the
  event-date interval. Refund wastage is already reclassified by the existing
  reversal/wastage entries; it is not added again from refunds. Unknown cost is
  unavailable; known subtotals remain separately labelled.
- Low stock uses the as-of ledger quantity with the current active/archive state
  and current reorder threshold. These catalogue settings are not historical.
- Branch stock, waste and adjustments/transfers always include all cashiers and
  categories. Only sales usage follows the selected cashier and current catalogue
  category as a whole-order filter, matching the daily summary's scope.
- Sales usage includes fully paid completed orders in the selected completion
  period. Actual is their original gross negative sale_deduction ledger quantity.
  Theory is immutable ingredient quantities saved at completion, including variants
  and modifiers. Returns through the selected end date are separate, and never
  reduce gross deductions or theory. This isolates deduction discrepancies from
  refund reclassification and prevents a later return rewriting an earlier close.
- Legacy/no-recipe lines are not reconstructed from today's recipes or actual
  movements. Any missing line makes complete theoretical totals/variance unavailable
  for the selected cohort; known recipe subtotals and missing counts remain visible.
- Variance means actual gross sale deductions minus saved theoretical quantities.
  It is a ledger/recipe consistency check, not measured physical consumption or a
  fraud finding. Period adjustments/transfers and waste are displayed separately.
- Different ingredient units are never summed. Quantities retain three decimals,
  costs six, using arbitrary-precision decimal arithmetic on the API. Flutter only
  displays and exports server values. Excel numeric cells have Excel's standard
  precision limits; CSV/PDF preserve the decimal text.
- Reports omit unsynced offline sales until synchronization. All branches, ingredient
  sources, order cohorts, actor names and filters are scoped to the authorized
  business. Source records paginate at 50 and hide stale rows while fetching.

## Files changed

- API: InventoryReportService; SalesReportsController dispatch and validation.
- Capture: OrderItem cast and SaleInventoryService snapshot inside the existing
  completion transaction. Stock deduction/payment transaction boundaries are unchanged.
- Schema: nullable order_items.recipe_usage_snapshot and stock branch/time/id index.
  No historical snapshot is backfilled or invented.
- Flutter: inventory_report.dart, inventory_report_screen.dart, repository method,
  Reports entry; CSV/numeric XLSX/branded four-column PDF use the shared exporter.
- Verification: InventoryReportsTest, inventory_reports_test.dart, independent export
  reader assertions, real MySQL CI selection and the populated upgrade/rollback rehearsal.

## Verification (disposable databases only)

```sh
cd backend-skeleton
php artisan test --filter='InventoryReportsTest|ProfitReportsTest|ActivityReportsTest|SalesReportsTest'
```

```sh
cd frontend
flutter analyze
flutter test test/features/reports
python3 tool/verify_report_exports.py
```

Tests cover stale caches, exact recorded costs, unknown pools, waste, gross usage,
returns, legacy history, recipe edits, rollback, paid-only filters, branch access,
DST/end boundaries, source pagination, numeric exports and phones at 100%/200% text.
CI also runs the full suites, disposable MySQL migration/isolation checks, Android
integration recovery and both supported iOS compile toolchains.

Before joint acceptance: apply the additive migration only to the disposable test
backend, run the matching frontend branch, then check Phases 3 and 4 together. Do
not migrate the main top_coffee_pos database during development/testing. No merge
or production migration is authorized by this phase's implementation request.

## Scale

The branch/time/id ledger index supports dated scans. Replay uses ordered 250-row
pages and stores state per ingredient; paid sales load items/movements in 250-order
batches without per-order queries. Date selections remain bounded to 366 days, but
closing valuation must read earlier ledger history. Daily rollups and invalidated
large-range caching remain the aggregation phase; this implementation does not
claim constant-time valuation for a long ledger. Export and UI financial totals
are never computed from pages in Flutter.
