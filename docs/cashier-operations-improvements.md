# Cashier and operations improvements — 15 October 2026

## Scope and owner choices

The owner authorized the proposed cashier, recovery, stock and manager improvements while pausing physical device testing. The existing kitchen-display removal remains intentional. Work applies to the GitHub candidate, not the uncommitted local UI.

The owner confirmed USD and Cambodian riel and a fixed shop rate of US$1 = 4,000៛. USD remains the accounting unit. Riel tender shortcuts enter exact USD-cent equivalents only; the display does not introduce a change-rounding policy or rewrite historical payments. The centralized build setting KHR_PER_USD can override the approved default for a future deliberately configured build. A different rate requires a new acceptance review; historical receipts retain their saved USD amounts.

## Ranked findings and changes

| Severity | Finding or opportunity | Result |
|---|---|---|
| High | Inventory requests omitted the selected branch, and late actions could capture a new branch around an old ingredient. | Authorize and capture account/branch scope for loading and mutations; discard stale scope responses/actions. |
| Medium | Inventory buttons did not distinguish manage and adjustment permissions. | Separate view/manage/adjust controls and finite, three-decimal validation; stock mutations retain the ledger path. |
| Medium | Dashboard readers issued repeated requests and could mix snapshots. | Share the in-flight request and recreate branch-scoped readers. |
| Medium | Uncertain printer output was presented with a generic Retry Print action. | Preserve durable queue status in the exception; direct uncertain output to Check Paper/COPY while allowing failed-before-send retry. Payment remains successful. |
| Medium | Manual drawer access and automatic attempts lacked durable command accountability. | Require a manual reason, save actor/branch/time before hardware, associate automatic attempts with a sale, and upload idempotent command evidence. No physical sensor confirmation is claimed. |
| Medium | Shift cards and saved actions exposed IDs, raw timestamps and request paths; closing cash was hard to interpret. | Authorized cashier names, explicitly device-local times, plain action labels, expected/count/difference preview, movement reasons and expandable technical details. |
| Medium | Sync views did not clearly separate pending and review states or identify recent confirmation. | Scoped counts and device-recorded server acknowledgement times; legacy acknowledgement times remain unknown. |
| Medium | An unauthenticated API request from a browser could try to redirect to an absent login route. | API authentication returns JSON401 independently of Accept; ordinary web redirect behavior is retained. |
| Medium | Nonfinite cash inputs could crash a currency preview, and the pinned footer could exceed a keyboard-shortened body. | Reject nonfinite tender values, guard conversions, and constrain the footer to its actual parent viewport. |
| Low | Checkout required scrolling to reach completion; the phone cart permanently consumed selling space. | Pin total/actions and make the phone cart expandable; keep tablet two-pane layout. Compact toolbar controls retain tooltips. |
| Low | Fixed quick amounts could be below the amount due. | Exact plus sufficient USD amounts and clearly labelled riel note equivalents. |

## Product improvements

- Cashier flow: keep both receipt choices reachable, expand the cart for edits, preserve the existing guarded and idempotent payment path.
- Offline recovery: show saved-on-device vs server-confirmed, retain references/conflicts, and give explicit recovery actions without deleting uncertain payments.
- Printer recovery: distinguish failed, sent and uncertain output. Printer acknowledgements do not prove paper output. Receipt retries never submit payment or replay automatic drawer pulses.
- Drawer accountability: the POS Drawer activity action opens the current cashier/branch journal, including upload review and explicit telemetry-only retry. A permanently rejected record does not block later valid uploads. Durable local evidence precedes a pulse; offline uploads are telemetry only. Records remain under the original cashier and branch. This is device-reported evidence, not tamper-proof hardware sensing.
- Shift close: show authoritative cash components and a read-only counted-versus-expected preview; the server validates final settlement.
- Inventory: lazily show a bounded list of actual products using a low-stock ingredient, including optional modifiers. These links do not estimate remaining servings or availability. Useful restock filters and urgency sorting, branch-safe movement actions, no direct cached-stock editing.
- Manager dashboard: put actual scoped saved-order/receipt exceptions and server low-stock counts above statistics, with direct actions. Counts for device queues explicitly cover this account/device, not all cashiers.
- Visual consistency: reuse existing theme/button components, labels, tooltips and responsive layouts instead of replacing local presentation work.

## Validation and exact patches

Exact changes from the preceding candidate are available in the [GitHub compare](https://github.com/sticky268/Top-Coffee-POS/compare/1863af211ad8af5ba4140073be9e5019dec16d20...codex/checkout-ui-polish). The PR check results identify the final tested commit.

New regressions cover branch/account races, shared dashboard requests, inventory permissions/quantities, USD/riel cents, nonfinite input, short keyboard windows, cart editing, uncertain receipt recovery, shift names/cash comparison, legacy and current sync acknowledgements, drawer authorization/idempotency/local persistence and API browser401 handling.

The populated MySQL rehearsal includes the new drawer table, verifies upgrades/rollback/reapplication and keeps the pre-upgrade data checks. CI uses isolated databases; no existing main or rehearsal database is migrated by this work.

## Release boundaries

No physical testing was run for this batch at the owner's request. The owner previously confirmed manual drawer opening, automatic cash-sale opening and receipt reprint without drawer reopening on USB Test120.1; those results do not certify the new candidate.

One additive cash_drawer_events migration requires rehearsal and approved deployment before central drawer uploads are available. Application-side evidence remains local while the server is unavailable. The user's running port8001 backend, local checkout and generated Flutter plugin files are untouched.

Production hosting, public HTTPS URL, release signing, backup/restore evidence for that environment and monitoring delivery remain deployment work requiring real environment choices. See production-readiness.md. No credentials, provider connection, tax policy or fake stock data were invented. PR11 stays draft and unmerged.
