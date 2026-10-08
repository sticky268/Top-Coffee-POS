# Business isolation review

The public product is a business POS for owners and staff. Customer ordering remains outside scope. Kitchen Display remains removed. Public launch also requires onboarding, distribution, hosting and operational acceptance; passing this review does not provide those services.

## Ownership and access

Products, categories, customers, suppliers, expense categories, modifier groups and audit logs now have an explicit business owner. “Global” customer/category/supplier records mean shared across branches of one business, not shared across businesses. Business-owned models filter authenticated reads and route binding. API creation assigns ownership from the authenticated actor; controllers do not accept a client-selected business owner.

Branch-specific orders, ingredients, tables, expenses and purchases retain the separate business and staff-assignment scopes. Administrators can access branches of their business, not other tenants. Existing foreign or unresolved category/product/customer/supplier IDs are rejected before creating links. Product variants must belong to the product being updated. SKUs are unique within a business, so independent businesses may reuse a SKU.

Staff and branch controllers already constrain ownership. Login and existing token use reject inactive/missing businesses and corrupt cross-business staff assignments. Token login checks the supplied credentials without relying on a previous request's authentication guard. Subscription data belongs to the signed-in user's business; unit definitions and plans remain shared reference data. Loyalty settings are selected through an authorized branch, and customer loyalty/history is protected by customer ownership.

Product-photo metadata and replacement operations are protected through their owning product. New uploads use business-specific paths. **Photo URLs still use the public storage disk:** these are public assets, not authenticated private file delivery. This review does not certify confidential file hosting. Expense attachment upload/download is not implemented by the current API. Private file delivery, if required, needs its own design and acceptance.

## Legacy migration

`2026_10_08_000001_add_business_ownership` adds nullable ownership columns and a per-business SKU index. It infers ownership from branch relationships, related orders/purchases, category ownership and audit actors. Unreferenced records are assigned automatically only when exactly one business exists. Ambiguous/multi-business shared records remain unassigned and hidden; the migration does not choose an arbitrary owner or rewrite financial history.

Run `php artisan pos:tenancy-check --json` after migration. It is read-only and returns a failing exit code for unresolved ownership or cross-business references. The production configuration check now includes this gate. Review any unresolved records explicitly; do not disable scopes to make the gate pass. Console imports must provide correct ownership. Demo catalog/expense seeders are limited to the demo business.

Rehearse on a verified database copy and compare existing values before updating any live checkout. Keep application writes stopped while applying the migration, because the new application queries the ownership columns. Retain the database/assets backup and use a reviewed restore procedure for rollback; the ownership migration deliberately refuses a rollback that would reintroduce global access or conflicting SKUs.

## Regression evidence

New API tests first reproduced foreign category modification, globally shared customer/supplier/category lists, audit-log exposure and foreign-category attachment. Coverage now includes read/write denial for foreign product/recipe/customer IDs, isolation of business-wide records and staff/audit lists, cross-business order/purchase/expense references, client ownership spoofing, unknown-owner quarantine, duplicate SKUs, image replacement protection, foreign variant IDs, invalid login assignments and inactive-business token reuse.

Migration tests exercise single-business backfill with unchanged original values and multi-business ambiguous/unattributed records that remain hidden and fail the integrity check. Existing fixtures name their business owner; the earlier checkout, inventory, receipt, loyalty and report assertions remain in place.

The final backend suite passed 321 tests / 1,433 assertions. The laptop MySQL staging rehearsal passed, comparing all 48 non-migration tables / 938 rows with original values unchanged. All seven owned tables had zero unresolved owners, and all fourteen checked cross-business link types had zero mismatches. Working source data stayed unchanged. This is snapshot evidence, not a guarantee of future imports or untested public deployment. PR #6 must remain unmerged until explicitly approved.
