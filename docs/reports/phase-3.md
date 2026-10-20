# Phase 3 - time analysis and cashier performance

Open Reports, choose a date/branch/cashier/category selection, then open
**Time & cashier performance**. Current and comparison calendar dates are pinned
to the loaded Sales report. Return to Sales to change filters.

## Accounting and attribution

- Financial amounts reconcile with Phase 1: fully paid completed orders only;
  recorded order total plus additional charges, including tax; separate discounts
  and refunds; net sales subtracts sale-linked refunds. Refunds follow the original
  sale cohort even if processed later. These are not event-date cash receipts.
- The original order cashier owns the sale, discount and sale-linked refund cohort.
  This measures the cashier's orders, not who approved or performed later actions.
  Source records separately show recorded refund and cancellation actors.
- Voids are non-financial counts, dated by the first matching cancellation audit
  event and attributed to the original order owner. Duplicate audit events do not
  inflate counts. Cancellations without reliable business-scoped audit history are
  excluded, not dated from mutable updated_at. Voids have no paid-sales amount.
- Category filtering selects whole orders by current catalogue category, matching
  Phase 1. Immutable historical item/category allocation remains in Phase 2 profit.
- The 7 x 24 heatmap uses each branch's local completion hour, Monday through
  Sunday. Repeated DST hours combine; missing hours remain zero. Quarter/half-hour
  timezone offsets are handled by converting each stored UTC timestamp on the API.
  Combined reports add matching local weekdays/hours from authorized branches.
- Comparisons are period totals, not adjusted for the number of each weekday in
  the period. All 168 cells, previous values and zero-baseline states are returned.
- Discount/refund rates count affected paid orders divided by paid orders. Void
  rate is audited voids divided by paid orders plus audited voids. Multiple refunds
  on an order count as one refunded order. Changes in rates are percentage points.
- A review flag requires at least 20 own and 20 peer observations, a rate of at
  least 10%, and a rate greater than twice the other cashiers' rate. Branch/category
  scope is preserved; the cashier filter does not narrow the peer baseline.
  No flag is a fraud finding. Prior-only cashiers remain visible at zero.
- Unsynced offline orders are absent until synchronization. No inventory balances,
  stock movements, order completion or payment behavior is modified.

## Files changed

- API: ActivityReportService and SalesReportsController dispatch/validation.
- Flutter: activity_report.dart, activity_report_screen.dart, SalesReportsRepository
  and the Reports entry button. Existing date and access filters are reused.
- Tests: ActivityReportsTest, activity_reports_test.dart, independent export reader
  assertions and the MySQL CI test selection.

CSV/Excel contain every heatmap cell, exact numeric money, cashier metrics,
comparisons, rate denominators/policy, branch/date/filter context and generation
time. PDF uses labelled four-column tables and omits cells with no paid orders in
either period; that omission is explicitly labelled. No nonzero cell is omitted.
Cashier names are literal text in Excel and formula-safe in CSV.

## Verification

Only use disposable testing databases:

```sh
cd backend-skeleton
php artisan test --filter='SalesReportsTest|ProfitReportsTest|ActivityReportsTest'
```

```sh
cd frontend
flutter analyze
flutter test test/features/reports
python3 tool/verify_report_exports.py
```

CI runs the full suites, real MySQL reporting/isolation/migration checks, Android
builds and recovery, and iOS tests/builds on both supported toolchains. Phone tests
cover normal/200% text, pinned source filters, pending pagination, errors and retry.
Independent readers check exact numeric export cells and PDF comparison labels.

## Scale

The API streams ordered 250-order batches and bulk-loads refunds, with no per-order
SQL and no financial calculation in Flutter. Date ranges remain bounded to 366
days. The activity source count also streams the selection to preserve filtering.
Existing order/date, payment/refund and audit action/reference indexes are used.
Daily rollups, invalidation and large-range caching remain the later aggregation
phase; this phase does not claim to implement those materialized summaries.
No schema migration or main database operation is required by this phase.
