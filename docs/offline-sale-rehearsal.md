# Offline sale and recovery rehearsal

This automated acceptance uses a disposable GitHub Actions Android emulator and
fresh SQLite API database. It does not use a shop, staging, Windows rehearsal
service, real payment provider, printer or cash drawer. Do not run these mutating
integration tests against an existing installation or database.

## Run and evidence

The **Daily operations integration** workflow runs on relevant PR changes. To
repeat it, open Actions → Daily operations integration → Run workflow and select
the reviewed PR branch. GitHub creates a fresh runner/emulator/database. This is
an integration run, not deployment. Record the commit and successful run URL.

The workflow installs dependencies, runs migrations and the testing-only
`IntegrationFixtureSeeder`, then executes:

```sh
python3 frontend/tool/run_operations_integration.py
```

That command deliberately requires GitHub Actions, `APP_ENV=testing`, SQLite,
the exact checkout `backend-skeleton/database/ci.sqlite`, dedicated synthetic
fixture identities and an unused local port8000. It accepts no target URL or DB
argument. It starts/stops only its own PHP child. It never kills an existing
listener. Do not defeat its guards to run it on a shop computer/server.

The runner invokes `flutter test` for the existing cashier, read-only operations,
manager approval and native print recovery flows, plus four invocations of
`integration_test/offline_sale_recovery_test.dart`, with
`--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1` and
`--dart-define=OFFLINE_PHASE=prepare|queue|restart|recover` (one phase per process)
and `--no-uninstall`. Flutter integration tests otherwise uninstall the app on
teardown; keeping it installed is necessary to test actual restart recovery.
Each command launches the actual app with real secure storage, SQLite, Riverpod
providers and HTTP client. The test refuses another API address. No mocked Dio
adapter, injected auth token or production test endpoint is used.

Between phases the host runs `adb shell am force-stop com.example.top_coffee_pos`
and checks `adb shell pidof com.example.top_coffee_pos` is empty. These commands
stop the **disposable emulator app** while retaining its data and Android
Keystore. Do not use them on a cashier's active device.

The runner writes `frontend/build/security/offline-rehearsal.json` only after
all phases, independent database assertions and existing integration flows pass.
Download the **offline-rehearsal-evidence** Actions artifact; it contains only
synthetic aggregate counts/balances, with no bearer tokens or keys. Failure does
not publish a successful evidence file. The failure-only API log helps diagnose
the disposable run.

## What is exercised

1. **Prepare online:** cashier A signs in through the UI, opens a $20 shift and
   loads both $3.50 drinks into the real per-user/branch catalog cache. The app
   confirms a verified shift is durably saved before accepting offline cash.
2. **Outage:** the host stops its API, independently verifies it is unreachable,
   and starts a new Android process. The cached session/catalog remain usable.
   Checkout saves two distinct cash intents with original UUIDs, expected total,
   operator and shift. It displays “Order saved on this device”, never “Payment
   Successful”. Switching to branch B and invoking sync exposes/sends none of
   branch A's requests; returning to A restores both waiting entries.
3. **Restart while still offline:** another force-stop/new process restores both
   exact original UUIDs/payloads/fingerprints/timestamps. Raw SQLite values have
   the authenticated-encryption prefix and do not expose the UUIDs. Independent
   server queries still show zero orders/payments/deductions in this tenant.
4. **Reconnect and conflict:** while the API remains stopped, the host changes
   only the dedicated changed-drink fixture price to $4.50. After API restart,
   normal sync confirms the stable $3.50 sale and retains the changed sale as
   “Needs review” following a real server409 response. Neither price nor UUID is
   rewritten. Bulk Sync now twice resends neither confirmed nor review entries.
5. **Replay and operator isolation:** replaying the accepted request's exact
   UUID/payload twice over HTTP returns the same order. “Retry original request”
   sends the unchanged conflicted intent and retains it for review. Cashier B,
   although authorized for the same branches, sees an empty personal queue and
   gets409 with the original-cashier instruction when attempting A's original intent. A signs back in and finds its
   original confirmed/review entries.
6. **Independent ledger proof:** host SQL requires exactly one completed order,
   one $3.50 cash payment ($5 tendered/$1.50 change), its original cashier/branch/
   open shift, and one recipe movement of −0.250 litres. Cached stock equals the
   stock-movement sum: A19.750 litres, B20.000. The conflicted drink has no server
   order, payment or stock deduction. This is checked separately from API parsing.

The fixture's opening inventory uses `StockMovementService`; tests do not edit
`current_stock`. All users/passwords are explicitly synthetic `.invalid` CI
fixtures, guarded by a fresh testing database; no real credentials are created.
The existing MySQL suites separately test transactions and concurrent replay;
this emulator flow uses SQLite and is not a substitute for those tests.

## Limits and owner acceptance

An unavailable API exercises a real transport failure; it does not certify every
Wi-Fi/cellular failure, a committed response lost in transit, OS upgrade,
low-storage or power-loss scenario. Exact accepted-request replay tests server
idempotency, without claiming that a lost acknowledgement was injected here.
Branch switching uses the same application action as BranchContextBar; checkout,
login, shift opening and pending-order/retry controls use real UI taps.

Journal values are encrypted; SQLite metadata/key names are not full-file
SQLCipher. These checks do not certify protection on an unlocked/rooted tablet.
Session revocation still requires server contact, and cached access never grants
server authority. This run uses cash bookkeeping only, no payment gateway.

Owner/operator must repeat on the actual approved tablet/release and staging
branch: short network loss, app force-stop/reopen without clearing data, reconnect,
review/resolve a price/stock/closed-shift conflict, and confirm a single sale in
shift/stock reports. Never create a replacement sale or collect another payment
for an uncertain intent. Record reconciliation and manager sign-off before
clearing acknowledged entries, uninstalling, resetting or wiping a device.
Physical receipt/COPY, English/Khmer rendering, paper/cut and drawer acceptance
remain manual. See [pre-pilot checklist](pre-pilot-checklist.md).
