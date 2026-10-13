# Reliable café operations — implementation review

Status: locally implemented, awaiting full runtime validation and authorization to publish to the public GitHub repository. This is the first implementation batch in the broader improvement plan; it is not a production release.

Base: `feature/kitchen-order-updates`, commit `d97c5acbf08ab633324622ac44ad853d2b1a1c6e`.
Working branch: `codex/reliable-cafe-operations`.
PR #6 must remain unmerged without the owner's explicit approval.

## Implemented in this batch

- Cashier shifts: opening cash, cash in/out with reasons, closing count, frozen expected balance, cash difference explanation, and manager review.
- Cash sales and refunds associate with the acting cashier's shift. Existing clients can continue operating without a shift; owner reports flag cash payments outside shifts. New client requests retain the original known shift, including an explicit unassigned state, through offline retries.
- Permission-controlled partial/full refunds and additional charge corrections. Original payment amounts and sale totals remain intact. Extra products must be recorded as a new sale so inventory is consumed correctly.
- Refund inventory disposition: retain consumption, restock unconsumed ingredients, or reclassify consumption as wastage. Inventory disposition is allowed only on the first full-sale refund. Partial refunds retain consumption.
- Proportional reversal of earned loyalty points. Already spent points become refund debt, offset against subsequent earnings, instead of creating a negative spendable balance.
- Durable correction requests on the device. Uncertain requests keep their original UUID and payload; changing account/branch cannot replay somebody else's request. A later permission failure cannot discard an earlier uncertain financial operation.
- Stock counts reject stale recorded balances. Transfers lock both balances, check branch access and matching active ingredient names, and convert compatible standard units. Transfers represent goods already received, not a shipment awaiting receipt.
- Weighted-average ingredient cost from purchases, optional stock-count valuation, movement-time cost snapshots, and sale-item cost snapshots. Unknown cost remains unknown rather than becoming zero.
- Product variants can scale the base recipe using a positive quantity multiplier. Existing configured modifier recipe rows are included when present on order items; the modifier editor and cashier option selection are future work.
- Recipe availability and ingredient cost views for base products and active variants. These are estimates per product, not reservations or a guarantee that simultaneous carts can all be fulfilled. Normal transactional stock checks still apply at sale completion.
- A cashier workspace with direct takeaway, dine-in, orders, shift and saved-order actions. Navigation hides unrelated management actions according to the current user's permissions; backend permissions remain authoritative.
- Branch selection and saved-order status in the application shell.
- Daily operations reporting for selectable 1/7/30-day periods and accessible branch comparison. Receipts, refunds, ingredient consumption and wastage use their own transaction dates. Ingredient margin excludes wastage and operating expenses; unpriced records are visible.
- Physical and electronic receipts include supplemental charges, recorded refunds and net paid amounts. Completed sales with financial adjustments cannot be edited through the old item-adjustment endpoint.
- Backend transaction/isolation tests, frontend recovery/dialog/workspace tests, and a real Android integration workflow covering login → opening shift → drink sale → cash reconciliation.

## Validation completed here

- PHP syntax parsing: 24 changed/new PHP files, no syntax errors.
- Dart parser/formatter: changed frontend source and added tests parse successfully.
- Four executable Dart model checks passed: variant multiplier persistence, legacy variant defaults, receipt reconciliation and financially adjusted order flags.
- `git diff --check`: clean.

## Validation still required

- Run the complete Laravel test suite against SQLite, then concurrency-sensitive scenarios against MySQL. SQLite tests cannot establish production row-lock behavior.
- Run `flutter pub get`, `flutter analyze`, all frontend tests and an Android build. Update `pubspec.lock` after resolving the new SDK integration-test dependency.
- Run the Android integration workflow against its disposable testing database. The fixture seeder refuses non-testing or populated databases and is never invoked by the normal DatabaseSeeder.
- Inspect the new screens at phone/tablet widths and validate physical receipt/Khmer printing on the café's hardware.
- Test migrations against a copy of existing data before deploying. New historical costing fields intentionally start unknown; do not fabricate old ingredient costs.

Local Flutter startup was blocked by automatic approval review because dependency startup attempted a cloud instance-metadata request. PHP runtime installation was blocked by network policy. Public GitHub branch/source upload was also rejected by automatic approval review even after verifying account/repository ownership; it requires explicit approval for public source disclosure. No runtime test pass or successful upload is claimed.

## Operation and rollout rules

Card/QR payments and refunds are cashier-recorded. This batch does not integrate a bank or execute provider refunds. Staff must perform any corresponding provider transaction separately and confirm the outcome before recording it.

Opening shifts is currently a staged adoption workflow, not a mandatory server requirement for every legacy checkout. A closed known shift rejects late submissions rather than silently charging a later drawer. The device blocks shift closing while its own saved orders/operations need confirmation. Other devices are not coordinated by a server-side terminal registry yet.

Full-sale stock returns use the recorded original consumption, not today's recipe. A variant multiplier scales all base ingredients together; it is not an independent per-variant recipe. Stock transfers require the same ingredient name and compatible units; this should eventually use a shared ingredient catalog identity.

Historical receipts show the original sale plus appended corrections. Existing general sales reports retain their established behavior; the new operational report explicitly reconciles receipt/refund dates and displays unassigned cash and unknown cost.

## Remaining broader improvements

After this batch passes its gates: add configurable cashier modifiers/notes and popular-product shortcuts; per-variant recipe overrides; shipment/receiving stock transfers; richer refund item selection and approval requests; terminal coordination for closing shifts; persistent printer job recovery; and production monitoring/backup/release verification. Each should be a complete, tested follow-on batch rather than being represented as finished in this PR.

## Proposed review action

Publish this batch to a separate branch in `sticky268/Top-Coffee-POS`, open a draft PR targeting `feature/kitchen-order-updates`, and run CI. Publishing discloses the changed source because the repository is public. Do not merge this batch or PR #6, and do not deploy, until explicitly approved after validation.
