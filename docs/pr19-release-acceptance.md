# PR #19 release acceptance record

This is the current candidate register for `codex/manage-menu`, stacked on
`codex/reports-time-cashier`. Keep both branches. A prepared procedure is not a
completed acceptance check. No production deployment or merge has occurred.

## Candidate verification

Baseline 5482e7c failed Flutter tests on Android and both iOS toolchains:
`SliverFillRemaining` requested intrinsic dimensions from a summary containing
`LayoutBuilder`. Backend, MySQL, MariaDB and manager-PIN format checks passed.
Android acceptance also stalled on a repeated visit to the lazy PIN form.

The corrective candidate replaces intrinsic measurement with viewport-aware
minimum-height constraints in new/open orders. It scrolls before repeated PIN
settings interactions. New cart regressions cover 1, 5 and 10 distinct long Khmer
item names at normal and 200% text, short viewports and discount expansion.
Record exact final commit and CI links in PR #19; never carry an earlier green
status forward to a changed candidate.

## Eight-step completion register

| Step | Remote evidence / prepared work | Required acceptance before release |
|---|---|---|
| 1. Code and CI | Exact-head Flutter analysis/tests, backend, strict MySQL/MariaDB, native builds and emulator workflows | All required checks green on one candidate; inspect every failure |
| 2. Order layout | Compact cart regressions, phone/tablet/dark/large-text screenshots | Review final previews; device check with 1/5/10 distinct items, Khmer names and modifiers |
| 3. Sales workflows | Checkout, held orders, cancellation/refund and manager approval tests | Device operator repeats scenario sheet below against disposable data |
| 4. Business records | Transaction/report/inventory backend suites; independent report readers; emulator ledger checks | Same-order reconciliation with actual configured branch recipes and payment methods |
| 5. Hardware | Native printer transport and iOS build checks | Actual paper, Khmer, COPY and drawer tests on owner's hardware |
| 6. Recovery | Emulator API-outage, process restart, replay/conflict and print-queue checks | Signed device build repeats restart/outage without duplicate sale/payment/deduction |
| 7. Release/hosting | Existing production/signing/backup/monitoring kit linked below | Owner supplies host/domain, permanent app identity and signing; verify HTTPS, restore and alerts there |
| 8. One-counter pilot | Shift scenario and reconciliation sheet below | Owner/staff operate one counter and sign off full-shift reconciliation |

## Disposable sales rehearsal

Use a separate test business/database, never a live branch. Record candidate,
operator, device, branch, opening stock and opening cash; use synthetic customers.

1. Open shift. Create takeaway with a recipe item, quantity 2, variant and
   modifier; apply an authorized discount. Complete using an enabled payment
   method. Record order reference and charged amount.
2. Create dine-in, save, reopen, change quantity, save and review/pay. Confirm
   saved edits and authoritative checkout price. Repeat Complete Sale and
   Complete & Print separately. COPY must not create a sale or drawer pulse.
3. Cancel an unpaid order; refund a paid test order with the configured manager
   approval. Test cashier denial, wrong PIN and lockout. Confirm business scope.
4. Compare receipts, transactions, sales totals and item/category reports for
   these exact references. Check each recipe deduction against stock movements;
   validate refund movement according to implemented refund policy. Record
   unknown/historical recipe cost warnings rather than treating them as profit.
5. Repeat every enabled payment mode and applicable currency/rounding setting.
   Check tender/change and insufficient-tender errors. Do not enable unsupported
   payment modes merely to pass this sheet.
6. Disconnect API, create a permitted offline order, force-stop/reopen, reconnect
   and replay. Confirm one order, one payment and one stock deduction for UUID.
   Retain conflicts for resolution; do not blindly resend a cash payment.

## Hardware acceptance

Start with COPY of an existing disposable paid receipt. Check Khmer names,
Niradei regular/bold, width, totals, cut and readable QR if configured. Verify no
extra sale. Test cash-sale drawer pulse and authorized manual opening separately;
manual opening intentionally requires no reason and creates no new manual log.
Test printer off/on, queue retry and app restart without duplicate jobs. Record
printer model, connection type, paper width and photographs of actual output.
Native transport tests cannot sign off physical paper or drawer behavior.

## Hosting and signed installation handoff

Use [production readiness](production-readiness.md),
[production setup](production-setup.md),
[backup and recovery](backup-and-recovery.md),
[Android signing](android-release-signing.md),
[iOS readiness](ios-release-readiness.md) and [deployment kit](../deploy/README.md).

Needed from owner: chosen server/domain, isolated staging access, backup provider
and key custody, alert destination/operator, permanent Android/iOS identifiers,
and private signing access. Never put keys, passwords or bearer tokens in this
record. No host purchase, external message or production mutation is performed
by this document. Rehearse migrations and restoration on an isolated fresh copy
before approving live activation. Verify the signed app works without ADB reverse
or a development PC; loopback development URLs are not production connectivity.

## One-counter pilot sign-off

Record opening cash/stock, operator, device and exact signed version. Operate one
full shift, including the scenarios above. At close compare completed sales less
refunds with payment totals, cash movements and counted drawer; reconcile stock
movements, expenses and report date/branch scope. Record every discrepancy and
its explanation. Block expansion for unexplained money/stock differences,
duplicate orders, failed recovery or unreadable receipts. Retain rollback and
backup evidence. The owner/manager signs the result; CI cannot run a real shift.
