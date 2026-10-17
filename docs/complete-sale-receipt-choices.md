# Complete sale receipt choices

The checkout screen offers **Complete & Print** as its primary action and **Complete Sale** as its secondary action. Both use the same guarded, idempotent payment submission and validation. Complete Sale does not automatically print; the paid screen still offers receipt actions.

Complete & Print starts one receipt request when the paid confirmation screen mounts, only after server confirmation. Pending offline orders do not print automatically, including after background sync. Cash drawer behavior is independent of the receipt choice: confirmed positive cash payments use the existing automatic drawer attempt. Receipt retries never submit payment or pulse the drawer.

Printing errors leave the payment successful and show **Retry Print** plus **Check Print Queue**. Existing durable queue rules prevent resending acknowledged/uncertain originals; for an uncertain job, inspect paper and use the queue's COPY flow. A printer acknowledgment does not prove physical paper output.

## Validation

Widget coverage checks automatic print is opt-in, starts once across rebuilds, and a printer failure can retry receipt work while retaining paid status. Checkout phone/tablet, text scale and theme tests exercise the primary action and check both actions are disabled for insufficient cash. Existing controller tests cover concurrent submissions and offline/payment idempotency.

Hardware owner previously confirmed manual drawer opening, automatic opening for cash completion, and receipt reprint without drawer reopening. These confirmations apply to the preceding build. The new two-choice checkout requires installation and physical acceptance of the updated test APK.

Physical check: complete a rehearsal cash order with Complete Sale (drawer opens, no paper), then a separate rehearsal cash order with Complete & Print (drawer opens, receipt prints). With printer unavailable, confirm paid status persists and retry only printing after restoring connectivity.
