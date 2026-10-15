# Launch work register — after the security review

The owner authorized continuing feasible remote work. This maps the ten ranked
actions in `security-review-2026-10-15.md`, not ten unseen business decisions.
Exact final CI is recorded in draft PR #11. No live deployment, merge, host/account
purchase, real credential generation, DB grant change or external message occurs
by preparing this kit.

| # | Workstream | Implemented/prepared | Evidence still needed to close the launch item |
|---|---|---|---|
| 1 | Authorization/money/replay attack paths | Bearer-token tests and MySQL contention/isolation tests | Owner's staged pilot acceptance |
| 2 | Sessions/revocation | Expiry, installation rotation, scoped revocation, login throttle/audit | Staff enrollment and actual lost-device drill |
| 3 | Offline payload protection | AES-GCM migration/reopen/tamper/key-loss tests and Android recovery | Signed retained-queue/OS-lock acceptance; full-file metadata stays visible |
| 4 | Dependencies | Patched Composer lock/audit gate; Dart inventory | Ongoing updates and discontinued transitive package migration |
| 5 | Catalog/audit evidence | Shared-price scope and transactional product/recipe audit | External immutable audit retention/checkpoints |
| 6 | Cash/shift/discount controls | Server/UI cash-only and readiness controls | Apply/verify intended business configuration on authorized staging/target |
| 7 | Android/device controls | Backup exclusions, release network/screen code, signing guards | Permanent ID/key custody, signed device/OS-lock acceptance |
| 8 | Host/runtime DB permissions | Nginx/FPM/systemd kit; per-table grant renderer and real MySQL denial tests | Chosen host, actual fresh-account grants/TLS/firewall verification |
| 9 | Encrypted backups/monitoring | age backup/recovery, integrity tests, health signals/service templates | Real key custody, off-site storage, timed restore, backup freshness and alert delivery |
| 10 | Privacy/incident/pilot | Proposed operating defaults and procedures below | Named operator/contact, approved privacy/retention, pilot/deployment approval |

## Proposed defaults

Reviewable preparation defaults, not silently applied settings or legal retention:
one branch, cash-only settlement, USD accounting with the already approved 4,000
riel display equivalent, manager-approved discounts/refunds, required shifts,
shop-owned supported Android and two-minute OS idle lock. Do not infer change
currency/rounding policy from equivalents. The current pilot requirements make manager PIN for void/refund a Must-have;
it is now implemented with own-account enrollment, persistent lockout and
per-action prompts; real per-branch enrollment still gates deployment. No shared admin
login or offline manager approval is introduced.

Propose 14 days of restricted operational logs and 30 days of encrypted backup
versions for owner review. No automatic financial/audit/customer deletion or
backup pruning is active by default (the new daily job requires explicit retention approval). These are **not approved legal retention periods**.
Resolve legal holds/retention before deletion automation. Proposed synchronized
server targets remain RPO 15 minutes/RTO 4 hours until proven. A drained-write
snapshot alone cannot meet 15-minute RPO during continuous trading.

## Privacy procedure

Until a publishable notice/contact and retention policy are approved, pilot staff
should use guest checkout and avoid optional contact/loyalty collection. This
document does not disable the existing customer module. Never use real customers
in CI/test exports. Inventory staff/audit data, local queues, receipts, exports
and backups alongside the server customer table.

Before collection, the notice must identify the actual business/contact, fields,
purposes, staff access, storage/providers, exports, retention, backup limitations
and request process. No company address, provider, legal basis or promise of
immediate complete erasure is invented. The business needs qualified local review.

For a request: verify the requester privately/proportionately; locate server
customer/loyalty records, receipts/exports, device queues and backups; check
financial/legal retention; record an approved response; minimize/anonymize optional
contacts while preserving required financial evidence. Never delete orders,
payments or stock movements to erase a name. Existing delete endpoints do not
prove complete erasure. Rehearse the approved process on synthetic data first.

## Incident procedure

1. **Contain:** the operator records time, affected devices/accounts/branches and
   safe UUID/request references. Revoke stolen-device sessions; disable compromised
   users as appropriate. Isolate suspected devices/printer networks. Preserve
   tablet data, logs and queues rather than wiping them.
2. **Reconcile:** retain original pending UUIDs and off-site/audit evidence.
   Separate server-confirmed payment from print/drawer warnings. Have a manager
   reconcile offline cash; do not invent replacement completed sales for conflicts.
3. **Recover:** use separate recovery keys/credentials on an isolated empty target;
   verify financial/stock/audit totals and elapsed restore time. Drain writes for
   approved cutover. Roll back schema-compatible code, not financial migrations
   over real new transactions.
4. **Rotate deliberately:** revoke affected tokens; roll exposed DB/provider/
   signing credentials through a tested plan. Never blindly regenerate `APP_KEY`
   or journal keys; encrypted records can become inaccessible. Signing loss needs
   an update/re-enrollment plan, not an unplanned package-ID switch.
5. **Review/communicate:** the named owner/operator decides required customer,
   staff/provider/authority communication and follow-up. No messages are sent
   by these tools. Record root cause, reconciliation, alert gaps and corrections
   before reopening or expanding the pilot.

## Evidence required for external gates

- Exact source/green CI, sanitized production/health checks, actual server URL/
  versions and verified TLS renewal. Never paste private credentials.
- Actual fresh runtime grants with audit UPDATE/DELETE/DDL denial on isolated
  staging; separate migrator/backup/recovery permissions and immutable evidence.
- Trusted ciphertext/version hash, separate key access, off-site retrieval,
  timed restore and reconciled totals. Prove failure/staleness alerts arrive.
- Permanent signed package/certificate metadata and current physical acceptance:
  OS lock, backup/screenshots, retained offline queue and printer COPY from an
  existing paid receipt. No new real sale is required.
- Named incident owner/contact, approved retention/privacy/cash procedure,
  pilot fallback and explicit merge/deployment approval.

**Completion wording:** implementation and synthetic CI may be called complete
for their named source. A live control requires its actual environment evidence.
Do not describe all ten launch items as closed while this evidence is missing.

## Prepared pilot operations follow-up

Production setup, encrypted daily/off-site orchestration, isolated restore proof,
Telegram/HTTPS monitoring, device-revocation drill and signing instructions are
prepared in docs/production-setup.md and docs/pre-pilot-checklist.md. These are
files/tests, not evidence of real provider or hardware acceptance. Manager PIN void/refund step-up is now implemented; see manager-pin-approval.md.
The business-settings command and release script require actual migrated,
privately enrolled branch approvers before readiness can pass.
