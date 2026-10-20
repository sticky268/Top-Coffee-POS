# Reports menu and sales history

The Reports route now opens a grouped menu inspired by the supplied tablet references. Sales & revenue links to the existing sales summary, daily/monthly history, profitability/product performance and branch comparison. Operations & management links to time/cashier performance and inventory. Every entry opens an implemented report; the menu itself does not need a successful API request.

Sales history defaults to the last 30 branch-local calendar days, newest first. Monthly shows all twelve months of a server-resolved year, with year selection back to 2000 and future months explicitly marked upcoming. Each row shows paid-order count, item units and original order totals including tax, before subsequent refunds/additional charges. Category filters select whole orders and all their item units. Refunded units stay in the original sold quantity. Legacy orders with no items still count as paid orders, with zero recorded item units. No sales or missing fields are invented.

The server adds order/item counts to the existing timeline query. Item quantities aggregate per order before joining, so multiple items cannot multiply order totals. The derived table is restricted to the same authorised/paid/completed/date/filter cohort. Branch-local windows and existing integer money calculations remain unchanged. The highest positive order total in the visible list receives a Top badge; ties all receive the badge and an all-zero list has none. Monthly future periods cannot be opened.

Tap a daily or monthly row for the existing full sales summary and order evidence. Analytical menu links use server-resolved current/previous dates and shared filters; Change filters opens Sales summary and returns to the analytical report. Branch comparison retains its all-accessible-branches scope. Branch changes clear incompatible cashier/category choices and pending history snapshots cannot replace the next branch's results.

All pages use the app theme. At narrow widths or large text sizes the amount stacks beneath the period details. Headers scroll with the content, leaving one standard app bar. This work changes presentation and read-only reporting queries; it adds no migration and does not write stock, payment or order records.

## Files

- ReportsHomeScreen / ReportWorkspaceScreen: grouped menu and direct analytical entry/filter return.
- SalesHistoryScreen: daily/monthly browse, year/cashier/category filters, top badge and period navigation.
- app_router.dart: Reports route opens the menu.
- reports_screen.dart: identifies the detailed page as Sales summary.
- Existing activity/inventory/profit/branch screens: optional filter callback for menu entry; existing navigation keeps its default behaviour.
- SalesReportService.php: timeline order counts and item quantities.
- SalesReportsTest.php: paid/cohort/category/cashier/month counts, multi-item totals and legacy orders.
- reports_menu_history_test.dart: menu without network, themed phone/tablet/large-text previews, history drill-down, no-sales, retry and branch race.

## Verification

Backend report tests run on SQLite memory, strict MySQL and MariaDB in CI. Flutter analysis and tests cover 360px/800px layouts, 100%/200% text, light/dark themes, monthly history and navigation. Existing time/cashier/inventory/branch tests and export-reader checks remain enabled.

On the physical iPhone, open Reports and verify each menu entry. In Sales history switch Daily/Monthly, choose another year, filter cashier/category and open a period. Confirm the row counts/totals against its full summary, check no Top badge for zero sales, and verify upcoming months are disabled. Then check report exports as before. Keep PR #18 unmerged until acceptance.
