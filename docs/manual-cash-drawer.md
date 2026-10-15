# Manual cash drawer

The New Order screen includes Open cash drawer below the top toolbar on phone/tablet layouts. It is shown to authenticated users with orders.create permission and access to the selected branch. It uses that branch's Receipt Settings printer destination and requires printing to be enabled.

Android sends the vendor SDK's openCashBox(0) command on the standard printer drawer connector. Connect a compatible drawer to the printer's drawer port; a standalone USB/Bluetooth drawer is not supported by the current Ethernet printer integration. The SDK method signatures were inspected in the bundled printer-lib-3.2.0.aar.

The command shares receipt serialization, rechecks user/branch/permission after connection, disables repeat taps and is never journaled or automatically retried after restart. It creates no order, payment, cash movement or receipt. The app reports command submission only; a printer response cannot prove physical drawer opening. If confirmation is lost, inspect the drawer before retrying manually.

Tests cover bridge rejection, permission gating, disabled printer, repeated taps, branch changes during connection, receipt queue interoperability and no automatic replay. Physical drawer opening still requires acceptance on the actual printer/drawer; hardware was unavailable. No changes to local edits, generated plugin files, databases or running services are required. PR remains draft and unmerged.

## USB-connected phone acceptance build

The POS validation workflow additionally publishes `top-coffee-usb-phone-test`. This debug-only app is visibly named **Top Coffee USB Test** and uses the separate application ID `com.example.top_coffee_pos.drawer_test`. CI verifies both in the packaged APK. It has its own local data and does not replace an installed POS application. The regular APK is uploaded before the USB variant is prepared.

The API is compiled as `http://127.0.0.1:8001/api/v1`, matching the existing PC test server reached with `adb -d reverse tcp:8001 tcp:8001`. Keep USB debugging authorized and the USB cable connected. Changes to the test label and HTTP network policy occur only in CI's disposable checkout; the test permits HTTP only to loopback hosts. Release signing and production URL requirements remain unchanged.

Install the separate test APK, use the intended rehearsal server account, select the correct branch, and configure its receipt printer destination. Ensure the drawer is attached to the printer's drawer port. On New Order, tap Open cash drawer once and physically check the drawer. Avoid creating orders/payments/stock adjustments for this hardware-only check. A submitted command is not proof of mechanical opening.

The owner's phone screenshot confirmed the test server is reachable through the USB connection. This verifies connectivity only; physical drawer acceptance remains pending until an observation is recorded. Local source changes, generated Flutter files, existing app queues, main/rehearsal databases and port 8001 services are not changed by the build process.
