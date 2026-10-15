# Cash drawer accountability

## Behavior

Manual **Open cash drawer** now asks for a reason before sending a command. A cancelled dialog or a reason shorter than three characters sends nothing. The request records the original cashier, selected branch, device time and reason without creating a sale, cash movement, payment or stock movement.

Confirmed cash sales retain the existing automatic drawer behavior. The journal links an automatic attempt to its server-confirmed order. An automatic attempt remains consumed before any printer connection or pulse, including when printing fails or the app stops. Existing consumed-attempt markers survive this update. Receipt reads, receipt copies and background order sync never trigger drawer commands.

Every command requires durable local audit evidence before hardware access. If this initial write fails, no command is sent. Result-recording failure leaves the initial evidence in place and shows an unconfirmed warning; it never causes an automatic retry.

The printer's synchronous pulse implementation is unchanged. **Command sent** means the printer interface reported that command bytes were sent. There is no drawer-open sensor. No UI or server record claims physical opening was confirmed.

## Offline and synchronization

Drawer audit evidence lives separately from payment and receipt queues, scoped to the original user and branch. While that cashier is signed in with that branch selected, an app worker uploads pending evidence with bounded exponential backoff. Upload retries send telemetry only. They cannot open the drawer, create another order or change financial totals.

The request pins the original session token and sends an expected cashier ID. The server checks the authenticated actor, current order-creation permission, assigned branch and business ownership. Evidence from another user or branch is not uploaded under the current cashier. If the original cashier does not return, access is revoked, or the app is uninstalled before upload, centralized evidence may remain incomplete. Local storage and device-reported evidence are not tamper-proof.

Acknowledgements are separate from event records. A delayed acknowledgement of an initial attempt cannot erase a newer command result. The server accepts idempotent repeats, rejects reused IDs with changed details and prevents a delayed initial status from downgrading a final status.

## Server evidence

The additive `cash_drawer_events` migration must be applied through the normal reviewed deployment process before the new telemetry endpoint is available. No migration is run by this change.

`POST /api/v1/cash-drawer-events` is authenticated and rate-limited. It accepts:

- `attempt_recorded`: durable initial evidence, outcome unknown.
- `command_sent`: device-reported successful command transmission.
- `unconfirmed`: a command attempt could not be confirmed.

Automatic events additionally require a completed order in the same branch and a positive cash payment processed by the original cashier. Historical refunded cash payments are accepted so a later refund does not invalidate delayed evidence. The endpoint never sends hardware commands.

Existing audit logs receive `cash_drawer.<status>` events with cashier, branch, reason, optional order ID, device timestamps and the explicit evidence label `device_reported_command_only`. Server receipt time is kept separately from device time; clock drift does not rewrite server timestamps. Physical confirmation is always false.

## Validation

Feature tests cover permission and branch/business isolation, actor substitution, manual reasons, trusted server fields, changed-payload conflicts, monotonic final outcomes, delayed refunded-sale evidence and absence of financial/stock side effects.

Flutter tests cover persistence across restart, offline retry/backoff, account/branch isolation, acknowledgement races, reason cancellation/validation, audit failure before hardware access, automatic sale markers and shared printer serialization.

Physical testing is deferred at the owner's request. This change does not replace the previous owner-confirmed drawer hardware checks with new claims.
