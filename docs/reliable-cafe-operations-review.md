# Reliable café operations — implementation review

Status: published with owner approval in draft PR #7. Automated results, including the added MySQL concurrency checks, are recorded in the PR. This remains a draft for review. This is the first implementation batch in the broader improvement plan; it is not a production release.

Base: `feature/kitchen-order-updates`, commit `d97c5acbf08ab633324622ac44ad853d2b1a1c6e`.
Working branch: `codex/reliable-cafe-operations`.
Draft PR: https://github.com/sticky268/Top-Coffee-POS/pull/7. Both this PR and PR #6 require explicit merge approval.

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
- Branch selection and saved-order status in the application shell. Short phone carts scroll to keep the order total and checkout action reachable.
- Daily operations reporting for selectable 1/7/30-day periods and accessible branch comparison. Receipts, refunds, ingredient consumption and wastage use their own transaction dates. Ingredient margin excludes wastage and operating expenses; unpriced records are visible.
- Physical and electronic receipts include supplemental charges, recorded refunds and net paid amounts. Completed sales with financial adjustments cannot be edited through the old item-adjustment endpoint.
- Backend transaction/isolation tests, frontend recovery/dialog/workspace tests, and a real Android integration workflow covering login → opening shift → drink sale → cash reconciliation.

## Validation completed here

- PHP syntax parsing: 24 changed/new PHP files, no syntax errors.
- Dart parser/formatter: changed frontend source and added tests parse successfully.
- Four executable Dart model checks passed: variant multiplier persistence, legacy variant defaults, receipt reconciliation and financially adjusted order flags.
- `git diff --check`: clean.
- GitHub CI: complete Laravel suite passed (339 tests, 1,533 assertions), including local-date refund reporting, spent loyalty points, transfer isolation and historical wastage costs.
- GitHub CI: Flutter dependency resolution and analysis passed; all 244 frontend tests passed, including recovery and compact phone cart checks.
- GitHub CI: all 18 café operations tests passed on MySQL 8. Separate-process tests additionally verify real InnoDB lock contention for duplicate refunds, competing refunds, partial refunds, shift closing versus charges, refunds versus charges, and competing transfers.
- Concurrency testing exposed repeatable-read snapshots that could over-refund a sale after an order lock wait. Refund eligibility/history, drawer totals and refund loyalty totals now use current locked reads inside their transactions.
- A populated previous-schema migration rehearsal passed upgrade, repeated migration, pre-adoption rollback and reapplication. It preserves all original columns in 14 tables, including historical financial records, stock, loyalty and Khmer text. New historical costing fields remain unknown.
- GitHub CI: final Android debug APK build passed. The real Android integration workflow passed login → open with $20 → sell a $3.50 drink with $5 tendered → close with $23.50 counted cash → awaiting manager review.
- The integration-test SDK dependencies in `pubspec.lock` were captured from the successful CI resolution; existing package versions were preserved.

## Remaining rollout verification

- Integration fixtures were used only in a disposable testing database. The fixture seeder refuses non-testing or populated databases and is never invoked by the normal DatabaseSeeder.
- Inspect the new screens at phone/tablet widths and validate physical receipt/Khmer printing on the café's hardware.
- Test migrations against a disposable copy of the actual café database before deploying. The CI rehearsal uses representative synthetic historical data, not the café database. New historical costing fields intentionally start unknown; do not fabricate old ingredient costs.

Local Flutter startup was blocked by automatic approval review because dependency startup attempted a cloud instance-metadata request; it was not retried. PHP runtime installation was blocked by network policy. Runtime validation therefore runs in GitHub CI. The owner explicitly approved the public branch/source upload and CI runs.

## Operation and rollout rules

Card/QR payments and refunds are cashier-recorded. This batch does not integrate a bank or execute provider refunds. Staff must perform any corresponding provider transaction separately and confirm the outcome before recording it.

Opening shifts is currently a staged adoption workflow, not a mandatory server requirement for every legacy checkout. A closed known shift rejects late submissions rather than silently charging a later drawer. The device blocks shift closing while its own saved orders/operations need confirmation. Other devices are not coordinated by a server-side terminal registry yet.

Full-sale stock returns use the recorded original consumption, not today's recipe. A variant multiplier scales all base ingredients together; it is not an independent per-variant recipe. Stock transfers require the same ingredient name and compatible units; this should eventually use a shared ingredient catalog identity.

Historical receipts show the original sale plus appended corrections. Existing general sales reports retain their established behavior; the new operational report explicitly reconciles receipt/refund dates and displays unassigned cash and unknown cost.

## Remaining broader improvements

After this batch passes its gates: add configurable cashier modifiers/notes and popular-product shortcuts; per-variant recipe overrides; shipment/receiving stock transfers; richer refund item selection and approval requests; terminal coordination for closing shifts; persistent printer job recovery; and production monitoring/backup/release verification. Each should be a complete, tested follow-on batch rather than being represented as finished in this PR.

## Proposed review action

Review draft PR #7 targeting `feature/kitchen-order-updates` with the passing code-validation runs. Do not merge this batch or PR #6, and do not deploy, until explicitly approved after validation.

## Reproducing the release checks

The Linux CI MySQL job runs `CafeOperationsTest`, followed by `OperationsConcurrencyTest|OperationsMigrationRehearsalTest`. Release checks require `RUN_OPERATIONS_RELEASE_CHECKS=1`, `APP_ENV=testing`, MySQL, and the database name `operations_testing`. They recreate that disposable database; never point them at a café database. Normal local/SQLite suites skip these opt-in checks.

The concurrency harness starts separate PHP HTTP-kernel processes with disposable bearer tokens and verifies that both requests are waiting on InnoDB locks before releasing the barrier. The migration rehearsal populates the previous schema, compares every original column after upgrade, and exercises rollback only before new operations records exist. It does not establish that rollback is safe after adopting the new workflow.
