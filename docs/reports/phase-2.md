# Phase 2 — historical profitability and product performance

Open **Reports → Profit & product performance** after choosing the sales period,
branch, cashier and category. The selection is pinned to the loaded calendar dates.
Go back to Sales to change filters. All calculations run on the API.

## Accounting contract

- Same fully paid, completed, authorized branch-local sale cohort as Phase 1.
  A completed order without settled payments is excluded. Original collected
  overpayments do not inflate revenue. Refunds and additional charges follow the
  original sale, even when recorded later.
- Revenue = original total − original tax + additional charges − refunds +
  proportionally refunded tax. Refunds above the original total plus additional
  charges are reported separately as non-sales refunds, not negative revenue.
  Additional charges have no separate recorded tax.
  This is ingredient gross profit, not operating/net profit or a tax return.
- Each order's gross, discount, tax, additional charge and refund amounts are
  allocated by original `unit_price × quantity`, using exact largest remainders
  with item ID ties. Zero-price orders use equal line weights. Refunds are **not**
  evidence that a particular product was returned. All amounts reconcile exactly
  across item, product, category and branch groups; no current recipe is consulted.
- Recipe COGS uses `order_items.ingredient_cost`, the total line cost recorded at
  completion, including variant and modifier consumption. Preserve six decimals
  through all aggregation and exports; only money labels round to cents.
- Full restocks reverse line COGS only when the order is fully refunded, marked
  disposed and every ingredient's `sale_deduction` ledger quantity nets to zero.
  Missing/unbalanced reversals make cost incomplete. Consumed and wasted refunds
  retain original ingredient costs. Waste reclassification must not be counted a
  second time in a future P&L report.
- Missing snapshots remain unknown: total COGS/profit/margin are null, never zero.
  Known-only COGS and unknown line counts remain visible. A real zero snapshot is
  known. No attempt is made to reconstruct history from current recipes/prices.
- The migration adds sale category ID/name/captured flag, populated inside the
  existing completion transaction. No old rows are backfilled. Old categories
  appear as **Historical category unknown**. Product/category renames and recipe
  changes cannot rewrite captured history. Category filters select individual
  historical items, unlike Phase 1's whole-order category filter.
- Units are originally sold units, not net units returned (refunds are order-level).
  Best/slow sellers rank units, with deterministic ID ties. Previous-only sellers
  remain visible at zero. Available unsold catalogue products are separate: the
  app has no historical availability intervals, so it cannot claim they were
  offered throughout a past period. Cashier filters also affect that interpretation.
- Popularity threshold is average units per selling product. Margin threshold is
  revenue-weighted margin among complete-cost products with positive revenue.
  Stars/volume/opportunity/review are descriptive, not automatic pricing decisions.
  Missing-cost and no-positive-revenue products receive no margin quadrant.
- Comparisons use the same elapsed previous period as Phase 1. Margin changes use
  percentage points; unknown costs and zero revenue have no comparable margin.

## Changed areas

- API: `SalesReportsController`, shared authorized `SalesReportService::selected`,
  `ProfitReportService`, integer `ReportAllocation`.
- Completion: `SaleInventoryService` captures sale category in the existing
  stock/payment completion transaction; inventory movements remain append-only.
- Migration: `2026_10_19_000002_snapshot_sale_categories`; populated release rehearsal
  now includes eight migrations, forward, rollback and reapplication.
- Flutter: `profit_report.dart`, `profit_report_screen.dart`, report repository and
  Sales entry button; CSV/numeric Excel/branded PDF, narrow PDF tables retain all
  fields. Source items are paginated and show branch-local timestamps.
- Tests: `ProfitReportsTest`, `profit_reports_test.dart`, independent export readers.
  Real MySQL workflow includes the new feature tests.

## Validation

Run only on a disposable test database, never `top_coffee_pos`:

```sh
cd backend-skeleton
php artisan test --filter='SalesReportsTest|ProfitReportsTest|CafeOperationsTest'
```

```sh
cd frontend
flutter analyze
flutter test test/features/reports
python3 tool/verify_report_exports.py
```

CI additionally runs the full backend/Flutter suites, real MySQL contention and
populated migration upgrade/rollback, Android native/recovery workflows and iOS
builds. CI results will be recorded in the PR after completion.

Device acceptance: compare a discounted/taxed mixed-category sale to source items;
refund part as consumed and verify proportional revenue; fully restock another and
verify zero retained COGS; change recipe/current category and verify old report is
unchanged; inspect missing-cost warning, best/slow/unsold, period comparisons and
all three exports. No production/main database migration is run by this change.

## Scale and subsequent work

Queries stream 250 orders at a time, bulk-load items/refunds/ledger per batch and
retain grouped results only, avoiding per-item queries and calculations in Flutter.
Detail allocation is recalculated server-side to preserve exact order allocation
before item filtering. This is linear in the selected sales; maximum range remains
366 days. Persistent daily rollups, cache invalidation after adjustments and
large-tenant performance tuning belong to the aggregation phase, not an assertion
that this implementation already has a materialized reporting warehouse.
