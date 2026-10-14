# Persistent printer queue

Receipt and unpaid-bill jobs are stored before connecting to the printer. The
SQLite store is already isolated by API URL; queue keys additionally include the
signed-in user and selected branch. Each job retains its printable snapshot,
including totals/refunds, item quantities, formatting and logo bytes.

Open **Print Queue** in the navigation menu, or use **Queue** on the receipt/bill
notification. Receipt Settings configures the printer for the selected branch.
Retries use that branch's current configured printer and record its IP in the
job. They use the saved document rather than fetching a changed sale.

- **Waiting:** saved but not attempted; resumes when the account/branch is opened.
- **Sending:** printer connection/transmission in progress; actions are disabled.
- **Sent — check paper:** SDK accepted the send; paper output is not proven.
- **Failed before sending:** nothing was handed to the print method; fix the
  printer configuration/connection and choose Retry.
- **Check paper — confirmation unknown:** the print call failed or the app was
  interrupted while sending. Inspect the paper; there is no automatic retry.
- **Printed — confirmed by cashier:** a person inspected and confirmed the paper.
- **Cancelled:** journal entry retained; cancelling never cancels/refunds a sale.

Repeated Print Receipt taps reuse an existing matching job. Receipt and bill screens also offer Reprint COPY for older documents whose original print predates the journal. This asks for confirmation and saves a labelled copy before sending. A deliberate reprint
uses **Reprint COPY**, asks for confirmation, and creates a labelled copy of the
saved document. If a changed receipt is printed after an acknowledged/uncertain
attempt, that new document is also labelled COPY. Bills keep their unpaid title.
An interrupted copy follows the same uncertain-result rules as an original.

One queue instance serializes sends across its accounts/branches and rechecks
scope after connecting. Switching account/branch does not allow sending an old
scope's jobs. Queued printing never submits an order, payment or refund. SDK
confirmation cannot provide exactly-once paper delivery: a lost response may
mean a document printed. Only manual paper checks and labelled copies can
resolve that uncertainty. This is a device-local queue, not server-wide printer
coordination or an OS background print service. Clearing app data removes it.
Diagnostic Test Print/Khmer/bitmap tests remain immediate printer diagnostics.

Validation covers duplicate enqueue/send taps, persisted failed/waiting jobs,
interrupted sends, uncertain-result handling, labelled copies, branch/account
isolation, scope switching during connection, immutable receipt/logo snapshots,
revised receipts and storage failures. UI tests check narrow uncertain-job cards
and the required copy confirmation. Real paper/Khmer output still requires the
physical printer.
