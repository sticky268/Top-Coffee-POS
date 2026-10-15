# Manager PIN approval for voids and refunds

Prepared in draft PR #11. No migration, real PIN enrollment, deployment or live
server operation is performed by this change. Staging/owner acceptance remains.

## Authority and approval

The **signed-in manager/admin enters their own PIN**. This preserves individual
accounts and the existing manager-session approval policy. A cashier token plus
someone else's PIN cannot gain manager functions. The manager must also have the
specific orders.refund/orders.cancel permission and access to the order's branch
in the same business. Scope checks run before PIN verification. There is no
shared shop PIN, remote manager ID supplied by a cashier, or reusable approval
badge/token. A PIN does not replace the account password or device-token expiry.

Production always requires this check for refund and held-order cancellation,
even if business manager controls were misconfigured. Local/testing businesses
can exercise legacy unprotected flows only while require_manager_controls=false;
the production business-settings gate still requires those controls enabled.
Discount approval retains its existing manager-session policy; this change does
not introduce PIN authorization for discounts, additional charges or stock edits.

## Own enrollment and reset

After a reviewed additive migration on staging, a manager signs in, opens
**Settings → Manager PIN**, and supplies their current account password, a new
6–12 digit PIN and its confirmation. Repeated or sequential digits are rejected.
No PIN is preassigned, printed, returned or created in a production seed. A
manager can reset only their own PIN with their current account password; they
cannot target another user ID. Five failed PIN/password-verification checks
persist a 15-minute lockout on the user row across devices/IPs. Own re-enrollment
cannot bypass an active lockout. API account/IP throttles provide another bound.

The server HMACs the PIN with APP_KEY and user/business binding, then uses
Laravel's configured password hasher. The PIN hash and lock fields are hidden
from user serialization and are not mass assignable. A database-only copy does
not contain the APP_KEY pepper. Protect APP_KEY and its independent recovery
copy; rotating it requires a deliberate manager-PIN reset plan. Password resets
or account deactivation clear the PIN and revoke existing tokens. Administrator
password reset is an incident-recovery action, not the own-PIN reset flow.

## Flutter, interrupted requests and offline behavior

Refund submission and manual retry ask for a fresh PIN. Both cancellation paths
(order detail and open-order editor) prompt too. The PIN goes only in the
**X-Manager-Pin request header**, never in saved operation payloads, SQLite,
secure-storage session snapshots, idempotency rows, audit details or cached
approval state. The existing session/branch guards remain in place. Inputs are
obscured, suggestions/autofill disabled, and controllers cleared/disposed. Dart
strings necessarily exist transiently in process memory; this is not a promise
of secure memory zeroization or protection from a compromised unlocked device.

The app can retain a refund's nonsecret intent/UUID after interrupted networking,
but cannot grant approval offline. A later manual retry asks again; the original
UUID is retained so a confirmed refund is never duplicated. Correctly denied
PIN requests do not create a financial operation record. Even replaying an
already successful UUID passes fresh manager/PIN checks before its stored result
is returned. No PIN is carried in the saved retry request. A lost cancellation
response should be resolved by refreshing order history before trying again;
cancellation itself keeps the existing status-conflict behavior.

Failure counters/audit commit before rejecting the request, separately from the
financial transaction, so a rejected refund cannot roll them back. Financial
approval audit, refund and financial effects commit together. Held cancellation,
table release and cancellation/approval audits now commit together as well.
A concurrent PIN reset invalidates the in-flight proof before mutation. Login
spike health signals include failed PIN checks, without exposing identities.

Do not add request-header/body logging or crash breadcrumbs containing
X-Manager-Pin, current_password, pin or pin_confirmation. Existing Nginx logs do
not include these headers/bodies; Laravel does not flash enrollment credentials.
Any future monitoring integration must explicitly redact these names as well
as Authorization and ordinary passwords. Do not log raw Dio requests/exceptions.

## Endpoints and verification

- GET /api/v1/auth/manager-pin: own manager enrollment/lock status, no-store.
- POST /api/v1/auth/manager-pin: own password-confirmed enrollment/reset, no-store.
- POST /api/v1/orders/{id}/refund and /cancel: fresh own PIN header when required,
  plus existing permission, business, branch, payment/order-state checks.

From backend-skeleton:

```sh
php artisan test --filter ManagerPinTest
php artisan pos:business-settings-check --json
```

The test command runs role/branch/credential/lockout/replay/audit rollback and
readiness regressions against disposable test data. The read-only checker now
examines real middleware/schema and **an enrolled, unlocked authorized manager
for every active branch**; it no longer has a hard-coded missing-feature failure.
Unconfigured branches still fail. Do not create fake PIN hashes to make it pass.

From frontend:

```sh
flutter test test/features/auth/manager_pin_prompt_test.dart test/features/operations/operations_repository_test.dart
```

These tests verify masked prompts and PIN-free durable retries. The full suite
and real MySQL feature tests remain required. Owner acceptance must enroll actual
managers privately, confirm both UI cancellation paths and a staging refund,
exercise lockout/retry/password reset, and rerun all production gates. Never test
real refunds, shift payouts or cancellation against a trading database.
