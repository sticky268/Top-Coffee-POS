# Manual cash drawer

The New Order screen includes Open cash drawer below the top toolbar on phone/tablet layouts. It is shown to authenticated users with orders.create permission and access to the selected branch. It uses that branch's Receipt Settings printer destination and requires printing to be enabled.

Android sends the vendor SDK's openCashBox(0) command on the standard printer drawer connector. Connect a compatible drawer to the printer's drawer port; a standalone USB/Bluetooth drawer is not supported by the current Ethernet printer integration. The SDK method signatures were inspected in the bundled printer-lib-3.2.0.aar.

The command shares receipt serialization, rechecks user/branch/permission after connection, disables repeat taps and is never journaled or automatically retried after restart. It creates no order, payment, cash movement or receipt. The app reports command submission only; a printer response cannot prove physical drawer opening. If confirmation is lost, inspect the drawer before retrying manually.

Tests cover bridge rejection, permission gating, disabled printer, repeated taps, branch changes during connection, receipt queue interoperability and no automatic replay. The owner confirmed that the manual button opened the real cash drawer from the USB-connected HONOR phone. This confirms manual hardware operation; automatic cash-payment acceptance remains separate. No changes to local edits, generated plugin files, databases or running services are required. PR remains draft and unmerged.

## USB-connected phone acceptance build

The POS validation workflow additionally publishes `top-coffee-usb-phone-test`. This debug-only app is visibly named **Top Coffee USB Test <run>.<attempt>** and uses a unique application ID under `com.example.top_coffee_pos.usbtest` for each build attempt. Earlier builds used `com.example.top_coffee_pos.drawer_test`. Separate identities allow installation alongside existing test copies despite CI debug-signing keys changing between runners. CI verifies both in the packaged APK. It has its own local data and does not replace an installed POS application. The regular APK is uploaded before the USB variant is prepared.

The API is compiled as `http://127.0.0.1:8001/api/v1`, matching the existing PC test server reached with `adb -d reverse tcp:8001 tcp:8001`. Keep USB debugging authorized and the USB cable connected. Changes to the test label and HTTP network policy occur only in CI's disposable checkout; the test permits HTTP only to loopback hosts. Release signing and production URL requirements remain unchanged.

Install the separate test APK, use the intended rehearsal server account, select the correct branch, and configure its receipt printer destination. Ensure the drawer is attached to the printer's drawer port. On New Order, tap Open cash drawer once and physically check the drawer. Avoid creating orders/payments/stock adjustments for this hardware-only check. A submitted command is not proof of mechanical opening.

The owner's phone screenshot confirmed the test server is reachable through the USB connection. The owner subsequently confirmed successful manual cash-drawer opening on the real printer/drawer. Automatic opening after a cash-payment completion still awaits physical acceptance on the refreshed build. Local source changes, generated Flutter files, existing app queues, main/rehearsal databases and port 8001 services are not changed by the build process.

## Automatic opening after cash payment

A server-confirmed completed new order or payment of a held dine-in order automatically requests the drawer when the confirmed payment contains a positive completed cash amount. Split payments with a cash portion are included. QR/card-only, zero-total, held, cancelled, rejected and offline-queued orders do not trigger it. Background synchronization never opens a drawer later; use the manual action for those cases.

The payment success view appears immediately. Printer work runs separately through the existing serialized printer connection; it cannot fail or repeat the payment. A failed or unconfirmed drawer attempt shows a **Payment completed** warning with instructions to inspect the drawer and use the manual button if needed. Receipt printing, retries, reprints and viewing history do not trigger automatic opening.

Before the automatic attempt, the device durably records the cashier/branch/order key. Duplicate callbacks, matching payment replays and an app restart cannot repeat that automatic attempt in the same app storage, even if the printer was disconnected. Failure to save this marker prevents the pulse. The manual action remains explicit and independent. This is a device-local at-most-once safeguard; it does not claim mechanical confirmation or coordination across different devices/reinstalled app storage.

Tests cover cash and split cash, exclusions, delayed server confirmation, paid-state independence from hardware, drawer failure warnings, queued offline requests, held-payment completion, repeated confirmation/restart, changing cashier/branch, storage failure and receipt COPY behavior. The owner has confirmed manual drawer opening from the phone. The next physical check is a controlled cash order in the rehearsal environment using the refreshed automatic-opening build.
