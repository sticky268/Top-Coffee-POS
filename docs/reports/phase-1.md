# Phase 1: daily and calendar-month sales reports

The new cashier Reports page uses `GET /api/v1/reports/sales`. `/reports` remains available to older installed clients. This branch builds on the pending compact-header/dine-in branch; it does not merge that work or change the main database.

## Date navigation

Today, Yesterday, This Week (Monday start), This Month, Last Month, rolling 7/30 days, custom dates (at most 366 days), a year selector and all twelve calendar months. A month opens daily totals; a day opens its paid orders. Presets resolve on the server. One branch uses its own current date; a combined report chooses calendar dates using UTC and applies those dates in each authorized branch's timezone. Boundaries are inclusive local midnight through exclusive next midnight, including DST.

Current-month views compare elapsed calendar days with the same day number in the previous month, capped at that month's end. Current-year views compare year-to-date with the same elapsed dates in the previous year, while retaining all twelve month rows (future months are labelled upcoming). This Week compares the same elapsed weekdays in the previous week. Closed calendar months/years compare full periods; other ranges compare the immediately preceding equal number of calendar days. Current partial-day data can change after refresh. A zero denominator displays New/no change rather than an invented percentage.

## Accounting definitions

* Gross = recorded order subtotal. Discounts and tax are separate. Order totals = gross minus discounts plus tax.
* Net = order totals + recorded additional charges - refunds linked to the selected original sales; includes tax. This is not net revenue excluding tax, recipe profit or P&L.
* Only completed orders whose settled original collections cover their total plus additional charges enter the sales cohort. Zero-value completed orders are permitted. Pending, failed and inconsistent refund-status payments do not count. Other completed orders appear in an excluded-record drill-down.
* Payment rows retain fully refunded methods, show collections/refunds/net separately, and count payment records rather than orders. A payment difference exposes overcollection instead of silently adjusting sales.
* Cash flow uses payment/refund transaction dates; a Tuesday refund of Monday's sale reduces Tuesday cash flow and the Monday sale's net result.
* Drawer reconciliation uses complete overlapping shifts independently of sales cashier/category filters. Opening + cash receipts - cash refunds + cash in - cash out = expected. Card/QR and printer drawer pulses do not enter the formula. It shows live ledger expected, recorded close expected, count and difference; the latest 50 overlapping shifts are shown explicitly. Shorter ranges expose earlier shifts. Event cash without a shift is flagged.
* Cashier filtering means original sale cashier. Category filtering currently means whole orders containing a product in that **current** category, and is labelled accordingly. Historical item/category allocation belongs to Phase 2.
* Report values use SQL DECIMAL/integer cents, exact PHP integers and fixed-decimal JSON strings. Flutter only formats values; no financial aggregation runs on the device. Monetary exports use exact numeric OOXML cells.
* Source drill-downs freeze the loaded calendar dates (including across midnight) and repeat authorization and filters; transaction-date collections/refunds also have source links; return 50 rows per page. Summary and source data are live snapshots and may change after a late sync or correction. No stale aggregate cache is introduced in this phase.

## Changed areas

Backend: `SalesReportsController`, `Services/Reports/{ReportMoney,ReportPeriod,SalesReportService}`, API route, transaction-date/shift indexes, `SalesReportsTest`.

Flutter: `sales_report` domain, `sales_reports_repository`, `sales_reports_controller`, Reports screen, source-record screen, shared export row builder/Khmer font fallback, report/widget/export/controller regression tests and independent Excel/PDF reader checks, including the fourth net-payment column. Existing large-text Reports coverage is updated to the new API contract. Button/chip text explicitly keeps the app's Inter family rather than falling back to the platform font.

CI: run the new feature tests on SQLite and real MySQL alongside existing checks.

## Validation commands

Backend disposable test DB only:

```sh
cd backend-skeleton
php artisan test --filter 'SalesReportsTest|ReportsTest|CafeOperationsTest'
```

Frontend:

```sh
cd frontend
flutter analyze
flutter test test/features/reports test/presentation/app_polish_test.dart
```

Full repository CI additionally exercises sales/stock atomicity, offline recovery, existing export readers, native printer recovery and iOS builds. The index migration must be rehearsed with the existing migration-rehearsal tool before any deployment; it is not run against the main database here.

## Device acceptance

Open Reports; check Today against a closed rehearsal shift. Browse a year, choose February and an individual day, then open a KPI's source records. Confirm cash/card split amounts and fully refunded methods. Compare a refund issued on another day in sales versus cash flow. Check cashier/category labels and clear filters. Export CSV/Excel/PDF and compare exact totals and Khmer branch names. Verify layout with large text and dark mode. Pending offline orders should appear only after successful sync and refresh.

Later phases add historical product margins, product/category allocations, heatmaps, cashier flags, inventory/P&L, durable daily aggregates and cache invalidation. Existing hourly, top-product and order-type breakdowns remain available using the new paid-order cohort and exact totals. Product ranking uses saved item names where present. Richer product profitability and heatmaps belong to Phases 2 and 3.
