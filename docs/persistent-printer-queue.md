# Persistent printer queue

Receipt and unpaid-bill jobs are stored before connecting to the printer. The
SQLite store is already isolated by API URL; queue keys additionally include the
signed-in user and selected branch. Each job retains its printable snapshot,
including totals/refunds, item quantities, formatting and logo bytes. Logos are stored once per account/branch as shared assets; job reads query only the matching SQLite key prefix.

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

## Native Ethernet transmission follow-up

The photographed PP-01-000129 receipt had a readable header followed by garbled
image bytes. The initial banding change (`e18ff35`) reduced raster height but
still queued SDK writes and used sleeps as a drain estimate. Inspecting the
bundled printer-lib 3.2.0 bytecode confirmed that Ethernet connects time out at
1,000 ms, `POSPrinter.sendData` queues writes, and even its synchronous mode
discards `sendSync` failure results. These are verified transport defects; they
do not establish the exact hardware cause of the photographed corruption.

The native channel now runs serially off the Android UI thread. Connection
opening gets up to three fresh attempts, closing each failed connection before
the next attempt. No receipt bytes or drawer pulses are sent by these retries.
The existing SDK remains responsible for ESC/POS encoding. Its single-buffer
and list-buffer sends are overridden to write synchronously, check every byte
count, and stop the session on failure. Image bands are 24 rows; outgoing data
is paced in chunks of at most 512 bytes. Feed/cut must complete the same checked
path before success reaches the Dart queue. A ten-second write watchdog closes
a stalled connection. A partial write, timeout or interrupted print stays
uncertain and cannot automatically replay the receipt or cut command.

`python3 frontend/tool/verify_printer_transport.py` exercises the production Java
writer without hardware: exact byte ordering, chunk boundaries, short/failed
writes, no replay or cut after failure, stalled-write cancellation and thread
interruption. Android JVM tests additionally exercise the real bundled SDK's
single/list dispatch through the checked subclass. The Android emulator also
opens a synthetic TCP printer on its own loopback address, sends a long receipt
through the real Dart/native bridge and SDK, and parses every raster header and
payload through the final cut. It rejects truncated bands, unexpected commands,
wrong widths and early/duplicate cuts. It cannot contact a shop printer or
submit a payment. Existing Flutter queue tests cover the resulting
failed-before-send versus uncertain states.

Physical acceptance is still pending. The later Android-to-printer connection
timeout can also be caused by the local network or printer connection limits;
connection retries cannot guarantee access to an unreachable TCP port. When the
owner is back at the device, inspect a **Reprint COPY of an existing paid order**
on the XP-N160II at its configured IP. Do not create another sale for this test.
CI checks do not certify paper output, Khmer shaping or physical drawer motion.
