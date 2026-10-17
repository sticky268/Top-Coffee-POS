# POS and checkout engineering review — PR #11

Reviewed remote baseline: d8bbe69ab47dedf466a4a6865ce6d5bf6ae7cebc.
Scope: POS checkout, held bills, monetary rounding, transactional writes,
duplicate/retried payments, offline outbox/sync, and branch/business access.
The user's uncommitted local presentation changes are outside this remote review.

## Verified findings and corrections

| Severity | Finding | Correction / regression evidence |
| --- | --- | --- |
| High | Split parts were rounded only after their aggregate was validated; 0.005 + 9.995 accepted a 10.00 bill but stored 10.01. Tiny positive parts could store zero. | Validate and persist the same integer cents; invalid parts roll back every order/payment write. CheckoutControlsTest. |
| High | Distinct offline sales with identical baskets reused one pending UUID. | Honor explicit checkout UUIDs; different sale IDs remain distinct, same-ID retries preserve the exact request. Legacy callers without IDs retain their previous recovery behavior. OrderOutbox tests. |
| Medium | Discounts above subtotal were rejected only when optional manager controls were enabled. | Enforce the financial bound on every Order save; full discounts remain allowed. CheckoutControlsTest covers checkout and hold with controls disabled. |
| High | A branch lock did not make MAX(order_number) see commits after an earlier MySQL repeatable-read snapshot. Concurrent checkouts could allocate the same number and return a retry failure. | Use a current locking read of the highest number after acquiring the branch lock. OperationsConcurrencyTest blocks two real requests and verifies numbers 1 and 2. |
| High | Held-payment loyalty and payment audit writes ran after the financial transaction committed; immediate checkout audit failures also left committed sales. | Commit checkout/payment, inventory, loyalty, table release and their payment audit writes together. Injected audit/loyalty failures verify rollback. CheckoutControlsTest. |
| Medium | A lost held-payment response led to a 404 on an otherwise identical retry. | A completed order acknowledges only matching persisted payment details and the same processing cashier; no payment, stock, loyalty or audit writes repeat. Changed payment details / another cashier return 409. Repository retries an uncertain network/server response once with the same payload. OrderTest, pos_repository_test, and real MySQL simultaneous held-payment test. |
| Medium | Immediate dine-in checkout accepted an occupied table and could create a separate paid sale while its held bill remained unpaid. | Check availability under the existing table lock. Existing held bill and inventory remain unchanged. OrderTest. |
| Medium | A late failure or stale retry could downgrade an acknowledged outbox record and erase its confirmed order ID. | Acknowledged journal state is monotonic. OrderOutbox tests. |

No Critical finding was confirmed in the reviewed remote scope. No speculative
findings are presented as defects.

## Authorization and duplicate-payment checks

- Creating, holding and paying orders require orders.create; viewing and editing
  have their existing server permissions.
- BranchScoped retains business isolation even for branches.view-all users.
  Subscription middleware rejects foreign branch and business-owned references.
- Creation replay requires the original branch, cashier and request fingerprint.
  A unique order UUID and transaction rollback prevent duplicate creation.
- Held payment locks the order before completing it. Matching concurrent retries
  return one receipt and leave one payment; other cashiers/details cannot replay it.
- Products, variants, customer and table availability/prices are resolved on the
  server. Expected totals reject changed-price reconciliation.
- Offline queues and catalog caches are isolated by cashier and branch. Sync stops
  on scope changes and preserves the original UUID, payload and shift.

## Validation and boundaries

GitHub Actions runs the full backend suite, disposable MySQL release checks,
Flutter analysis/tests, debug APK and Android operations integration. Final run
links and outcomes are recorded in the chat and PR description after completion.
Exact diffs and tests are available in the review commits.

Payments here are POS bookkeeping records for cash/card/QR; this review does not
certify an external acquiring-bank or payment-terminal integration. No schema
migration, database command, service restart, local checkout change, generated
plugin change or PR merge was performed. The rehearsal database and port 8001
were not accessed. Device validation of the user's uncommitted UI remains outside
what GitHub can observe.
