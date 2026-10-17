# Manager workflow emulator rehearsal

This acceptance runs the real Flutter app against Laravel's disposable CI SQLite
database. It complements feature/MySQL tests and physical owner acceptance; it
does not approve a pilot, a production migration or printer output.

IntegrationFixtureSeeder refuses non-testing or nonempty account/branch/product
databases and is never invoked by DatabaseSeeder. It creates a separate synthetic
manager business with cash shifts and manager controls enabled. Both manager
accounts start without PINs. No production PIN or owner signing/recovery key is
created. There is no test-only authentication route, PIN bypass or clock-control
endpoint in the API. The mutating integration test refuses any API URL other
than the Android emulator's fixed disposable endpoint.

## Automated flow

The daily-operations integration workflow migrates and seeds a fresh CI database,
starts Laravel on the CI runner and boots an Android emulator. The manager test:

1. Signs in through the login form and enrolls its own PIN through Settings,
   first proving a wrong account password is rejected. It checks the fields clear.
2. Uses normal authenticated API routes to prepare a synthetic shift, cash sale
   and held orders. These setup calls are not claims of testing checkout UI;
   the separate daily cashier test covers checkout UI.
3. Submits the real refund form, cancels approval, supplies a wrong PIN, then a
   correct PIN. It checks API financial state, one refund and PIN-free retry data.
   An exact-UUID API replay with fresh approval must keep one financial effect.
4. Uses both order-detail and open-order-editor cancellation controls. Wrong PIN
   displays the actual safe error and preserves the held order. Correct approval
   cancels it and releases the table. The orders remain in history.
5. Signs in as a second synthetic manager, enrolls through Settings and performs
   five wrong-PIN approvals. It verifies HTTP 429 and the visible lockout message,
   rejects even the correct PIN and blocks password-confirmed own re-enrollment.
   The held order remains unchanged. The 15-minute expiry itself is covered by
   Laravel time-travel feature tests; no production lockout duration is shortened.

The test observes only UUIDs and HTTP cancellation statuses; it does not log
headers, tokens or credential payloads. Credentials are synthetic fixture values.
No printer, cash drawer or external payment/alert provider is contacted.

## How to run

The `.github/workflows/operations-integration.yml` workflow automatically performs
the guarded CI setup. On an already prepared disposable emulator/backend only,
from frontend:

```sh
flutter test integration_test/manager_approval_test.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

This command drives actual UI and creates synthetic transactions in the CI API.
Do not forward that endpoint to a shop server or reuse real account credentials.
The test consumes its two unused manager fixtures; use a fresh isolated database
for a new run. It is not a read-only smoke test. Never reset the Windows/main/
rehearsal database or a trading database to prepare this acceptance.

Record exact source and completed workflow evidence in draft PR #11. Physical
tablet OS lock, retained queue upgrades, real credential enrollment and printer
COPY remain owner-only checks. The previously garbled physical receipt still
needs paper acceptance.
