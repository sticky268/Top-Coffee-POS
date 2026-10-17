# Top Coffee POS security review and launch gates

Reviewed starting point: `f79c1c74381a33c7845b80db5b7ea290f74bb577`, draft PR #11. This report is versioned with the fixes. The PR records final commit-specific CI results. No production deployment, merge, real database mutation, credentials, device enrollment, or payment-provider setup is implied.

## Assumptions and evidence boundaries

- One-branch, cash-only pilot on shop-owned Android devices is the proposed baseline authorized for preparation. Existing rehearsals retain manual card/QR bookkeeping. The host, operator, device policy and financial retention period remain unselected.
- KDS was intentionally removed. It is not a feature being certified or restored by this review.
- Laravel 12 / Sanctum 4, Flutter and MySQL are confirmed from source. Target production MySQL privileges, OS settings and network configuration have not been inspected.
- A compromised client is untrusted. Encryption protects extracted journal payloads; it cannot make a rooted running app, a dishonest authenticated operator, or an unauthenticated printer socket trustworthy.
- “Fixed” below means implementation and regression coverage are in this PR. Acceptance still requires the final green CI run and the unchecked launch gates. A risk marked **Needs review** is not a claim that an unseen deployment is vulnerable.
- Read paths include routes, authentication/subscription middleware, user management, branch/business traits, order creation/replay/pricing, payment/refund services, stock movement/recipe deduction, audit service/model/query filtering, product/recipe writes, reporting/export encoding, offline session/journal/outbox/sync, token storage, Android manifests/signing guards, readiness and backup helpers. This is not line-by-line certification of every controller or transitive dependency.

## Five end-to-end attack paths

| Attack | Trace and expected result | Automated evidence |
|---|---|---|
| Cashier refunds another branch's sale | Sanctum → active-business middleware → `OperationService::branch(orders.refund)` → branch-scoped locked order lookup → manager control → payment/refund transaction. Foreign branch selection is 403; own branch plus foreign order ID is 404. No refund/stock writes. | `SecurityAttackPathsTest::test_cashier_with_refund_permission_cannot_refund_another_branch_using_either_branch_id` |
| Client changes the total | Auth/branch checks → product/variant/branch prices resolved on server → integer-cent comparison with `expected_total` → transactional sale/payment/stock. Mismatching expected total returns 409. Extra client price/total fields do not become charged amounts. | `test_tampered_expected_total_rolls_back_and_extra_client_prices_never_settle_the_sale`; `CheckoutControlsTest` |
| Offline order is sent twice | Scoped encrypted outbox → original UUID/body/cashier → current server permission/branch checks → existing order fingerprint and unique UUID. Identical replay returns the existing sale; different actor/body returns 409. Server completion time is not taken from device time. | `test_same_offline_uuid_records_once_and_changed_content_or_actor_is_rejected`; `OperationsConcurrencyTest`; Flutter outbox/sync tests |
| Stolen tablet calls API | Token is bearer authority until it expires or is revoked. New logins have explicit expiry ≤12 hours; same installation rotates its prior token. Owner/manager can revoke sessions; the next request with a revoked token is 401. Local cached access is separately bounded and cannot override server revocation. | Session expiry, rotation, own-session IDOR, manager revocation and subscription-expired revocation cases in `SecurityAttackPathsTest` |
| Cashier calls manager API | Sanctum alone is insufficient. `/users`, `/reports` and staff role changes still enforce server permissions; mass-assigned role/branch fields do not grant authority. | `test_cashier_token_cannot_call_manager_endpoints_or_reset_its_role`; `UserTest`; `LaunchBusinessIsolationTest` |

## 1. Authentication and sessions

**Specific risk:** an extracted bearer token can outlive the shift; local logout without connectivity cannot revoke a server token. A per-IP-only login throttle can be bypassed by changing source addresses.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| AUTH-1 | Fixed: blank token-expiry configuration allowed unlimited tokens; login now issues explicit expiry, defaults to 720 minutes and rotates by installation UUID. | High | Medium after theft | Continued API access | Must-have for launch |
| AUTH-2 | Fixed: logout/revocation was behind subscription write restrictions. Own-session list/revoke/logout-all now remain available under authentication independently of subscription status. Managers can revoke only users they may manage. | High | Medium | Lost device remains authorized | Must-have for launch |
| AUTH-3 | Fixed: login lacked account-wide throttling and authentication audit events. Add IP/account buckets, equal-cost unknown-account hash checking and secret-free known-account events. | Medium | High on public API | Brute force and weak investigation evidence | Must-have for launch |

**Verification:** run `php vendor/bin/phpunit --filter 'AuthTest|SecurityAttackPathsTest|UserTest'`. Confirm response session lists contain neither plaintext tokens nor token hashes. Test logout when subscription is expired. Password reset/deactivation already revoke existing tokens; the reviewed login uses Laravel hashing.

**Applied PHP pattern:**
```php
$issued = $user->createToken($name, ['*'], now()->addMinutes(720));
$request->user()->tokens()->whereKey($session)->firstOrFail()->delete();
```
Actual code also locks the user, caps configured lifetime and writes security events transactionally. Schedule `sanctum:prune-expired` daily; expiration enforcement does not depend on pruning.

**Needs review:** target password hashing configuration/work factor, password recovery delivery and identity proof, admin MFA, and enrollment for individual PIN switching. No PIN-switch or public password-reset route was found in `routes/api.php`. Staff passwords remain the existing login method. App-specific idle reauthentication is not implemented in this pass; require a two-minute OS idle lock and individual staff handover for pilot. Per-staff app locking is a Should-have follow-up; it must preserve bounded offline access rather than silently erase queues.

## 2. Authorization and branch isolation

**Specific risk:** a manager's business-wide product model is not automatically branch-scoped. Editing a shared base price can affect branches the manager cannot operate.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| AUTHZ-1 | Fixed: shared global catalog edits could affect unassigned branches. Under the product lock, require authority over affected branches; retain own-branch price/availability overrides. Unlinked draft products remain editable by authorized product managers. | High | Medium | Cross-branch price/availability changes | Must-have for launch |

**Verification:** run `SecurityAttackPathsTest`, `ProductManagementTest`, `BusinessAccessTest`, `TenantDataIsolationTest` and `LaunchBusinessIsolationTest`. Tests use actual bearer tokens for hostile paths. Include both same-business foreign branch and foreign-business IDs. A denied write must leave financial/stock rows unchanged.

**Retained PHP pattern:**
```php
$branch = $ops->branch($request, 'orders.refund');
$order = Order::whereKey($id)->where('branch_id', $branch)->lockForUpdate()->firstOrFail();
```
Business scope remains separate from branch-assignment scope. `branches.view-all` does not grant access to another business. Manager refund controls supplement permissions rather than trusting a client `approved_by` value.

**Needs review:** complete endpoint-by-endpoint negative tests for controllers outside the traced paths, custom future roles, direct database integrations and any newly introduced policy/Form Request. Current reviewed actions mostly validate and authorize inline; absence of separate Policy files is not itself a vulnerability.

## 3. Money integrity and drawer controls

**Specific risk:** bookkeeping marked paid for an unverified QR/card selection, stale shared pricing, split-cent rounding, manager controls disabled in business configuration, and physical drawer commands sent outside the application.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| MONEY-1 | Fixed: production had no payment-method restriction. Production now defaults to cash-only, rejects disabled methods in `Payment::creating`, and returns allowed methods for checkout controls. Development rehearsals retain existing methods. | High | Medium | Fictitious electronic tender | Must-have for launch |
| MONEY-2 | Retained/configuration gate: optional controls permit cashier discounts under the configured threshold. Readiness now requires manager controls, cash shifts and zero cashier discount threshold for this pilot baseline. Existing databases are not silently changed. | High | Depends on target configuration | Discount/refund abuse | Must-have for launch |
| MONEY-3 | Needs physical/network acceptance: direct TCP printer/drawer access bypasses application approval. A reason or device-reported audit event is not proof of authorization or physical opening. | High | Medium on shared LAN | Unrecorded drawer access | Must-have for launch |

**Verification:** run `CheckoutControlsTest`, `OrderTest`, `CafeOperationsTest`, `SecurityAttackPathsTest` and Flutter checkout/drawer tests. Confirm disabled QR/card attempts roll back order/payment/inventory. Reconcile opening cash + cash receipts − cash refunds + movements with counted cash. Test maximum refund, partial refund, repeated refund UUID and paid-order correction. No invented tax policy is applied; current order tax is zero. USD is accounting currency; the existing 4,000៛ equivalent is display/tender assistance, not a second ledger currency.

**Applied PHP pattern:**
```php
abort_unless(in_array($payment->method, config('payments.allowed_methods'), true), 422);
```
Existing server pricing ignores client `unit_price` and charged `amount`. `expected_total` is a mismatch detector, not a trusted amount. Manual drawer UI now respects configured manager controls; modified clients and raw hardware access remain outside that UI boundary. Keep the physical key controlled and restrict printer-network access; a server approval cannot secure a raw socket by itself.

## 4. Inventory integrity

**Specific risk:** MySQL nontransactional tables or direct privileged SQL can defeat the stock service even when controller validation is correct. Concurrent deductions must serialize on the ingredient row.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| INV-1 | Needs review: target InnoDB engines, database grants and ledger/cache reconciliation are not observed in the future host. Code checks exist; no live-host pass is claimed. | High | Unknown | Rollback failure or stock drift | Must-have for launch |

**Verification:** run `IngredientManagementTest`, `CheckoutControlsTest`, `OperationsConcurrencyTest`, `ProductionDatabaseEngineTest` and the read-only `php artisan pos:production-check --json` on isolated staging. Inspect `SUM(stock_movements.quantity)` against each ingredient cache. Direct `current_stock` request fields are not accepted as the write source in the reviewed ingredient path.

**Retained PHP pattern:**
```php
app(StockMovementService::class)->record($ingredient, 'wastage', -$quantity, $actor->id, $reason);
```
The service locks the ingredient and appends a movement in a transaction; insufficient stock throws and the surrounding checkout rolls back. Recipe and variant multiplier deductions are covered by existing tests. Recipe edits now append an audit event in their transaction.

**Needs review:** real stock-count acceptance, opening-stock imports, any third-party writer and maximum-load deadlock/retry behavior. Offline stock currently remains subject to server stock validation: a shortage becomes a conflict, not an invented negative movement. A separate business process must reconcile any cash already collected offline.

## 5. Offline synchronization and local storage

**Specific risk:** loss of the tablet exposes cached sales/receipts, while deletion, corruption or key replacement could erase the only copy of unsynced work.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| OFF-1 | Fixed for active journal payloads: `offline_entries.value` was plaintext. AES-256-GCM now encrypts payloads with a device-secure stored random key, fresh nonces and row/API-bound authenticated context. | High | Medium after extraction | Customer/sale/receipt disclosure | Must-have for launch |
| OFF-2 | Fixed: offline session-cache reads now respect server-issued absolute session expiry in addition to the existing eight-hour cache age, token binding and rollback-time rejection. | Medium | Medium | Cached access beyond token lifetime | Must-have for launch |

**Verification:** run `journal_encryption_test.dart`, `local_store_test.dart`, `session_cache_test.dart`, outbox/sync/repository tests and Android `printer_queue_recovery_test.dart`. Tests inspect raw SQLite ciphertext, migrate legacy values, reopen, swap ciphertext across scopes, modify ciphertext remove the key and attempt a plaintext downgrade after migration. Errors must retain rows rather than return an empty queue. The Android test must prove queue reopen does not replay an uncertain print or lose a receipt.

**Applied Dart pattern:**
```dart
final box = await algorithm.encrypt(utf8.encode(payload), secretKey: key, aad: rowContext);
```
The legacy rewrite is transactional, uses SQLite `secure_delete`, and vacuums after commit. A secure-storage migration marker rejects later plaintext downgrades. This is authenticated payload encryption, **not SQLCipher/full-file encryption**. Row keys and schema remain visible. It does not certify removal from historical backups or storage snapshots. Generated legacy Drift tables are not used by the inspected runtime journal; populated data from an older app version needs explicit migration/reconciliation review.

Server replay still rechecks current authority, branch, fingerprint, prices, shift and stock. No automatic overwrite, backdating, forced conflict acceptance or offline manager approval is introduced. Revocation cannot instantly reach a disconnected device; the server refuses it on reconnection. A stolen unsynced tablet can still mean unrecoverable offline sales: server RPO cannot cover data never uploaded.

## 6. Laravel hardening and dependencies

**Specific risk:** debug pages, version-specific parser bugs, expensive unauthenticated work and unrestricted file handling may expose otherwise valid business logic.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| LAR-1 | Fixed: locked dependencies matched five advisory records across Laravel, CommonMark and Symfony HTTP Foundation/Yaml. Updated compatible versions and added a failing Composer audit gate. Reachability varies; no successful exploit is claimed. | High (maximum reported) | Depends on affected feature | XSS or denial of service | Must-have for launch |
| LAR-2 | Needs review: target debug/error/CORS/proxy/web-server/queue settings and an actual published-domain probe are unavailable. Development `.env.example` values are not evidence of production configuration. | High | Unknown | Secret leakage or exposed development services | Must-have for launch |

**Verification:** `composer audit --locked --format=json`; run the complete PHPUnit suite on the committed lockfile. Readiness rejects debug mode, unusable HTTPS, root/blank DB usernames, missing DB password, stale migrations and unsafe pilot controls. Never print `.env`, bearer tokens or private keys. Check public `/.env`, `/.git/HEAD` and PHP error responses only on authorized staging. Confirm responses do not disclose configuration. No public reset, webhook or upload endpoint beyond the reviewed route inventory is assumed.

**Applied PHP configuration pattern:**
```php
$checks['debug_disabled'] = config('app.debug') === false;
```
The production server must serve Laravel `public/`, disable PHP execution under uploaded assets and expose no phpMyAdmin/MySQL port publicly. Reviewed product images have image/size validation and business-prefixed storage; dimension limits, cleanup after partial file failure and adversarial file/polyglot testing still need review. Reviewed raw report aggregates use fixed expressions/bindings; searching for `Raw` is not a complete injection proof.

**Reviewed export path:** `frontend/lib/features/reports/data/report_exporter.dart` prefixes formula-like CSV text beginning with optional whitespace then `=`, `+`, `-` or `@`; quoting alone is not treated as protection. XLSX emits user text as escaped inline strings rather than formula elements. PDF uses Dart text/table widgets and a bundled font, not a server HTML renderer with remote-resource fetching. `report_exporter_test.dart` and independent workbook/PDF readers verify generated fixtures. Newly introduced exporters need the same review; this does not certify every spreadsheet application's re-save behavior.

**Needs review (Must-have for launch):** deployed CORS origins and trusted-proxy settings; secret injection/config-cache permissions; queue/scheduler OS identities and private management endpoints; sensitive-data filtering in HTTP, queue and monitoring logs; and any use of `request()->all()`, `unguard()`, raw SQL or privileged field assignment outside the traced controllers. The subsequent launch kit supplies an explicit empty-by-default browser-origin allowlist in `config/cors.php`; its effective framework/proxy response policy still needs staging verification. `User::$fillable` excludes role/permission fields but includes `business_id`; mass-assignment protection alone does not establish tenant authorization. Current controllers and middleware must remain the authority.

Known initial advisories: `GHSA-jh5r-qr3c-85q8`, `GHSA-97jj-33gv-5xf9`, `GHSA-3q6v-r5mr-hxv8`, `CVE-2026-108082`, `CVE-2026-109413`. The upgraded CI audit returned an empty advisory list; the final frozen lockfile must pass again.

## 7. MySQL and infrastructure

**Specific risk:** a passwordless/root runtime connection can modify financial/audit history directly; readable backup archives remain readable despite gzip and hashes.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| INFRA-1 | Fixed readiness gap: merely having a transactional DB was insufficient; the command now also rejects root/blank runtime usernames and missing DB passwords. Actual least-privilege grants still need review. | High | Unknown on target | Full financial database compromise | Must-have for launch |
| INFRA-2 | Confirmed tool boundary: `mysql_backup.py` creates private compressed archives with integrity/restore checks, but does not encrypt them. Encryption, off-site storage, key recovery and delivery are not configured. | High | Depends on storage access | Entire database/asset disclosure or loss | Must-have for launch |

**Verification:** operator inspects `SHOW GRANTS FOR CURRENT_USER`, network listeners/firewall rules and TLS on staging; application credentials must not have `GRANT`, `FILE`, global administrative or schema-migration rights. Rehearse migrations with separate credentials. Run the existing disposable backup/restore job, then repeat on the actual intended infrastructure with encrypted storage and measured restore evidence.

**Retained PHP probe:**
```php
app(ProductionReadiness::class)->hasTransactionalTables(DB::connection());
```
The read-only readiness command does not change grants, create users, convert engines or repair caches. Proposed targets are RPO ≤15 minutes for synchronized server data and RTO ≤4 hours; these are unproven objectives until measured. XAMPP stays a development environment. No host, domain, subscription or credentials have been purchased or invented.

## 8. Flutter and Android

**Specific risk:** an APK is inspectable, device backups can export app data and release traffic/screens can disclose credentials or customer details.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| MOBILE-1 | Fixed: manifest had no explicit backup/data-transfer exclusions. Main manifest now disables backup and supplies cloud/device-transfer exclusions. Cleartext HTTP is denied in main/release and allowed only in debug/profile development manifests. | High | Medium | Transfer of tokens/journal data | Must-have for launch |
| MOBILE-2 | Fixed code/configuration: release activities set `FLAG_SECURE`; Dio no longer follows redirects automatically. Screen-capture behavior still needs signed-device acceptance. | Medium | Medium | Screen/redirect disclosure | Should-have |

**Verification:** full Flutter tests/analyzer, Android compilation, encrypted SQLite reopen tests and a final signed release package inspection. Verify release `debuggable=false`, cleartext disabled, backup rules merged, screenshots/recents protected and signing identity correct. Existing signing/package-ID guards refuse an unconfigured release. Tokens remain in `flutter_secure_storage`; no provider secret is introduced into Dart defines.

**Retained Dart pattern:**
```dart
await const FlutterSecureStorage().write(key: tokenKey, value: token);
Env.validateProductionUrl(environment: 'prod');
```
The actual release entry point already forces production URL validation. APK obfuscation/R8 is not an authorization boundary. **Needs review:** release R8/printer reflection compatibility, signed physical-device behavior, security-supported Android fleet and remote wipe. Certificate pinning with backup pins/rotation is Nice-to-have initially; root detection is a risk signal, not proof of device integrity. The Dart inventory identifies discontinued transitive packages; it is not a clean vulnerability scan or proof those packages are exploitable.

## 9. Audit logging

**Specific risk:** a valid manager or compromised application DB identity can hide price changes or alter historical evidence.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| AUD-1 | Fixed: authentication/session events and product/recipe mutation evidence were missing. Added events; price/recipe audit failure rolls back the corresponding DB mutation. | Medium | Medium | Fraud investigation gaps | Must-have for launch |
| AUD-2 | Partly fixed: model allowed ordinary update/delete. Eloquent hooks now reject them and API has only audit reads. Query-builder/raw SQL can bypass hooks; target DB grants and external immutable retention remain unverified. | High | Medium after DB compromise | Evidence destruction | Must-have for launch |

**Verification:** run `AuditLogTest`, `AuditLogApiTest`, `SecurityAttackPathsTest` and checkout rollback tests. Ensure failure logs contain no submitted password/token. Validate actor, branch, order, amount, reason and server timestamps. Do not call a device-reported drawer command “physical opening confirmed.”

**Applied PHP pattern:**
```php
static::updating(fn () => throw new LogicException('Audit records are append-only.'));
static::deleting(fn () => throw new LogicException('Audit records are append-only.'));
```
No cryptographic tamper-evidence chain is claimed. An HMAC key on the same compromised application host alone would not solve administrator tampering. **Needs review:** append-only DB privileges, external log retention/checkpoints, actual report/export evidence and an explicit retention policy. Client-side exports cannot be certified by recording a server GET as “export successfully delivered.”

## 10. Payments

**Specific risk:** a cashier can assert `method=qr/card` without external proof. `verification=cashier_recorded` is deliberately not a provider settlement claim.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| PAY-1 | Fixed pilot default: unsupported electronic methods are rejected before financial commit. Real acquiring/KHQR confirmation, signed webhooks and reconciliation are not implemented or certified by this bookkeeping API. | High | Medium | False paid status | Must-have before enabling electronic payments |

**Verification:** `test_disabled_electronic_payment_cannot_create_a_paid_order`; ensure no order/payment/stock rows survive rejection. Retain existing refund/payment idempotency tests. Before enabling a provider, test invalid signature, duplicate event, wrong merchant/currency/amount/order, out-of-order notifications and reconciliation mismatch. No provider-specific implementation is guessed without its selected protocol.

**Applied PHP guard:**
```php
abort_unless(in_array($payment->method, config('payments.allowed_methods', ['cash']), true), 422);
```
Production readiness intentionally remains cash-only until a reviewed acceptance path changes that policy. Payment model fields inspected do not contain PAN/CVV storage. That does not certify the entire deployment or an unseen terminal integration. Never store card details or private webhook secrets in the Flutter bundle.

## 11. Privacy and compliance

**Specific risk:** customer/staff contact data and receipt exports can outlive their business purpose, while deleting financial evidence indiscriminately damages reconciliation.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| PRIV-1 | Needs review: no approved privacy notice, retention schedule or verified deletion/anonymization procedure was supplied. Existing customer APIs alone do not prove compliance or complete erasure. | Medium | Unknown | Excess retention or misleading notices | Must-have before collecting optional customer data |

**Verification:** inventory actual collected fields, receipts, local queues, exports, server backups and staff/audit records. Test a synthetic deletion request across those stores without removing legally retained financial evidence. Confirm shared/customer-with-null-branch semantics with the business; the reviewed customer helper treats those as business-wide.

**PHP minimization pattern, for the approved policy rather than a new automatic deletion job:**
```php
$contact = $request->only(['name', 'phone']); // Add other fields only for a stated purpose.
```
Default to guest checkout, keep loyalty/contact optional, restrict exports and exclude real customer records from CI artifacts. Decide legal retention with a locally qualified adviser. No invented retention period or assertion of Cambodian legal compliance is made.

## 12. Operations, rollout and response

**Specific risk:** a green unit suite does not detect a failed production backup, leaked device token, broken alert destination or unsafe rollback of financial migrations.

| ID | Issue | Severity | Likelihood | Impact | Launch priority |
|---|---|---|---|---|---|
| OPS-1 | Needs review: target monitoring/alert delivery, responsible operator, real backup schedule and production incident access do not exist in the inspected repository evidence. | High | Unknown | Prolonged compromise or data loss | Must-have for launch |

**Verification:** run an isolated staging restore/migration rehearsal, record recovery time and compare records/totals. Inject a synthetic failed-login spike, API 500 and backup failure; prove alerts reach the chosen operator. `/up` is liveness, not proof of database integrity or reconciled cash. Never send real customer records or credentials to a monitoring service by default.

**Existing PHP readiness entry point:**
```php
Artisan::call('pos:production-check', ['--json' => true]);
```
For a stolen device: revoke its sessions, disable the affected account if compromise is suspected, retain related UUID/audit evidence, secure the tablet/printer network, reconcile unsynced/uncertain sales and re-enroll credentials. Rotate only affected secrets with a tested rollout; do not blindly replace `APP_KEY`, which can strand encrypted data. Roll back application code only to a schema-compatible version; do not reverse financial migrations over new real transactions. The PR remains draft/unmerged and deployment requires separate approval.

## Top ten actions, ranked and estimated

Estimates are engineering effort, not promised elapsed time; infrastructure/account access is additional.

| Rank | Action | Effort | State | Priority |
|---|---|---|---|---|
| 1 | Prove branch/manager and money/replay attack paths | 6–10 h | Tests added; final CI required | Must-have for launch |
| 2 | Bound tokens, rotate installation sessions and expose scoped revocation | 5–8 h | Implemented and tested | Must-have for launch |
| 3 | Encrypt active offline payloads and rehearse migration/reopen/failure | 8–14 h | Implemented; physical retained-queue acceptance pending | Must-have for launch |
| 4 | Patch audited Composer packages and keep a failing audit gate | 2–5 h | Patched compatible lock; final frozen-lock audit required | Must-have for launch |
| 5 | Restrict shared catalog changes and audit prices/recipes | 4–7 h | Implemented with rollback regression | Must-have for launch |
| 6 | Require cash shifts/manager discount controls and cash-only pilot | 3–5 h | Server/UI/readiness prepared; target configuration unverified | Must-have for launch |
| 7 | Backup exclusions, release HTTPS/screen protection, device idle lock | 3–6 h | App changes present; OS/device acceptance pending | Must-have; screen capture Should-have |
| 8 | Least-privilege host/database and append-only audit permissions | 4–8 h | Readiness probes added; needs chosen host/operator | Must-have for launch |
| 9 | Encrypt/off-site backups and prove restore/alert delivery | 6–12 h | Restore tooling exists; storage/keys/operator still needed | Must-have for launch |
| 10 | Privacy/retention, incident ownership and controlled pilot | 4–8 h | Review/runbook supplied; business approvals remain | Must-have for launch |

Individual app PIN enrollment/switching and step-up approval UX: Should-have, roughly 8–16 h after the identity/offline handover policy is approved. Hardware-backed enforcement of drawer authorization requires a suitable controlled print bridge or hardware policy, not just an APK check. Pinning/root signals are Nice-to-have enhancements after the core launch gates.

## Three phases

1. **Before internal testing:** freeze this candidate's lockfiles; require green backend/MySQL/Flutter/native checks; rehearse encrypted journal migration on synthetic retained data; prove the five attack paths; run with test identities and no production credentials. Keep KDS removal intact.
2. **Before pilot branch:** choose host/operator and permanent HTTPS/signing identity; configure cash-only/shift/manager controls; set a two-minute OS lock and individual staff handover; restrict drawer/printer access; inspect runtime DB grants; run actual-host readiness, encrypted restore and alert-delivery tests; reconcile existing device queues before changing package or storage identity; approve minimal data collection and retention. One branch only, with a documented fallback and daily cash reconciliation.
3. **Before full launch:** review pilot exceptions and suspicious refund/discount patterns; verify another branch remains isolated under concurrency and device loss; meet measured recovery targets; rehearse code-compatible rollback and secret rotation; enable external payments only after provider-specific signature/idempotency/reconciliation tests. Review staff PIN/step-up UX before expanding shared privileged-device use.

## Pre-launch pass/fail checklist

Checked boxes indicate source changes/evidence prepared in this PR, not production acceptance.

- [x] Five attack paths have focused bearer-token tests.
- [x] New logins have explicit expiry; installation rotation and scoped revocation are implemented.
- [x] Active SQLite journal payload encryption, migration, scope binding and corruption/key-loss tests are implemented.
- [x] Backup/transfer exclusions, release cleartext policy and release screen protection are implemented.
- [x] Shared price mutation authorization and transactional price/recipe audit events are implemented.
- [x] Production cash-only defaults and strict pilot readiness checks are implemented.
- [x] Composer advisory gate and Dart dependency inventory are included in CI.
- [ ] Final candidate CI and frozen lockfile audit are green — see the PR's exact-commit checks.
- [ ] Physical signed-device backup/idle-lock/screenshot/retained-queue acceptance passes.
- [ ] Permanent HTTPS host/signing identity exists; MySQL/phpMyAdmin are not publicly exposed.
- [ ] Actual runtime DB grants enforce least privilege and protect audit evidence.
- [ ] Actual target `pos:production-check --json` passes without exposing configuration values.
- [ ] Encrypted off-site backup and separate-key recovery are proven with a timed restore.
- [ ] Selected alert destination/operator receives test incidents and backup failures.
- [ ] Refund/discount/shift/printer procedures and any offline cash conflicts are accepted by the owner.
- [ ] Privacy notice, financial retention and customer deletion/anonymization policy match actual behavior.
- [ ] Pilot approval, production deployment and merge are explicitly authorized.

## Automated cases and exact files

New backend tests: `backend-skeleton/tests/Feature/SecurityAttackPathsTest.php` covers hostile branch refund IDs, total tampering, repeat UUID/body/actor conflicts, manager API denial, session IDOR/revocation/expiry/rotation, subscription-safe revocation, manager revocation scope, account/IP throttle, secret-free auth auditing, audit model immutability, shared catalog authority, audit rollback and disabled payment rejection.

New/extended Flutter tests: `frontend/test/core/offline/journal_encryption_test.dart`, `local_store_test.dart`, `session_cache_test.dart`, auth repository tests, checkout polish and drawer button tests. Existing Android queue recovery now exercises the encrypted production store.

No files need to be pasted now: the repository was accessible. For future review, supply sanitized changes in this priority order:

1. `backend-skeleton/routes/api.php`, `bootstrap/app.php`, `app/Http/Controllers/Api/V1/Auth/AuthController.php`, `config/sanctum.php`, `app/Providers/AppServiceProvider.php`.
2. `app/Services/OperationService.php`, `CheckoutControls.php`, `app/Traits/BranchScoped.php`, `BusinessOwned.php`; one changed controller with its actual Policy/Form Request if introduced.
3. `app/Http/Controllers/Api/V1/OrderController.php`, `PaymentAdjustmentController.php`, `app/Models/Payment.php`, `config/payments.php`.
4. `app/Services/StockMovementService.php`, `SaleInventoryService.php`, `RecipeController.php` and stock-related migrations/importers.
5. `frontend/lib/core/offline/order_outbox.dart`, `order_sync.dart`, `local_store.dart`, `journal_cipher.dart`, `session_cache.dart`; there is no separate `/sync` route in the inspected inventory—replay posts to the original endpoints.
6. `app/Models/AuditLog.php`, `app/Services/AuditLogService.php`, `SessionSecurity.php`, `app/Http/Controllers/Api/V1/AuditLogController.php`.
7. `frontend/lib/core/network/api_client.dart`, `features/auth/data/auth_repository.dart`, `core/storage/app_database.dart`, `main.dart`.
8. `frontend/android/app/src/main/AndroidManifest.xml`, debug/profile manifests, backup XML, `app/build.gradle.kts`, `MainActivity.kt`.
9. `backend-skeleton/.env.example`, Composer/pub manifests and lockfiles, actual sanitized reverse-proxy/CORS/queue/scheduler configuration, DB grants, backup and alert configurations. Never paste actual passwords/tokens/keys.

## Sources checked for implementation guidance

Subsequent preparation: see [launch work register](launch-work-register.md) and
[deployment/recovery kit](../deploy/README.md). The new encrypted wrapper protects
backup publication; `mysql_backup.py` remains a plaintext staging/legacy helper.
The kit adds per-table runtime grants, explicit CORS and local health signals.
Actual host grants, off-site keys/storage/restore, delivered alerts, privacy
approval and signed physical-device acceptance remain external launch gates.

- Laravel 12 Sanctum: https://laravel.com/docs/12.x/sanctum
- Laravel deployment: https://laravel.com/docs/12.x/deployment
- Android Keystore: https://developer.android.com/privacy-and-security/keystore
- Android backup risks: https://developer.android.com/privacy-and-security/risks/backup-best-practices
- AES-GCM package API: https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html
- OWASP transaction authorization: https://cheatsheetseries.owasp.org/cheatsheets/Transaction_Authorization_Cheat_Sheet.html
- Advisory IDs/links and the exact audit JSON are preserved in the CI security artifact. Package advisories are supply-chain findings; application reachability must be evaluated separately.
