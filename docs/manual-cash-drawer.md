# Manual cash drawer

The New Order screen includes Open cash drawer below the top toolbar on phone/tablet layouts. It is shown to authenticated users with orders.create permission and access to the selected branch. It uses that branch's Receipt Settings printer destination and requires printing to be enabled.

Android sends the vendor SDK's openCashBox(0) command on the standard printer drawer connector. Connect a compatible drawer to the printer's drawer port; a standalone USB/Bluetooth drawer is not supported by the current Ethernet printer integration. The SDK method signatures were inspected in the bundled printer-lib-3.2.0.aar.

The command shares receipt serialization, rechecks user/branch/permission after connection, disables repeat taps and is never journaled or automatically retried after restart. It creates no order, payment, cash movement or receipt. The app reports command submission only; a printer response cannot prove physical drawer opening. If confirmation is lost, inspect the drawer before retrying manually.

Tests cover bridge rejection, permission gating, disabled printer, repeated taps, branch changes during connection, receipt queue interoperability and no automatic replay. Physical drawer opening still requires acceptance on the actual printer/drawer; hardware was unavailable. No changes to local edits, generated plugin files, databases or running services are required. PR remains draft and unmerged.
