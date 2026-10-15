# Pre-pilot acceptance — draft PR #11

Record exact commit, evidence links, operator, date and reviewer. **Empty boxes
mean unverified, not pass.** CI cannot sign off external or owner-only gates.
No merge, deployment or live-server operation is authorized by this checklist.

## Manager-PIN implementation and owner acceptance

- [ ] PASS / [ ] FAIL — Real manager-PIN enrollment, secure storage, throttled step-up,
  void/refund enforcement and positive/negative tests implemented (see
  manager-pin-approval.md). Record CI and staging evidence; real manager enrollment
  and hardware acceptance remain pending. pos:business-settings-check must pass
  actual per-branch enrollment coverage. Do not override it with a config flag.

## Automated/staging evidence

- [ ] PASS / [ ] FAIL — php artisan test, flutter test and composer audit --locked pass on exact commit.
- [ ] PASS / [ ] FAIL — Cross-branch/refund and cashier-to-manager attack paths denied;
  tampered totals rejected and duplicate offline UUID returns one sale/payment/stock movement.
- [ ] PASS / [ ] FAIL — MySQL grants generator applied to disposable account; normal CRUD succeeds,
  DROP/ALTER/TRUNCATE, audit UPDATE/DELETE and migrations writes fail.
- [ ] PASS / [ ] FAIL — Nginx public/ root, hidden/uploaded PHP boundary, HTTPS host/redirect,
  certificate renewal and query-free logs verified on staging.
- [ ] PASS / [ ] FAIL — FPM graceful drain, scheduler/queue stop/restart and failed-backup recovery tested.
- [ ] PASS / [ ] FAIL — Encrypted daily backup uploads to actual independent provider;
  immutable read-back matches and a restore compares every row count/hash/asset.
- [ ] PASS / [ ] FAIL — Real test, backup-failure, HTTPS-failure and failed-login-spike alerts
  arrive at the intended operator; cooldown/retry and external monitor outage detection tested.
- [ ] PASS / [ ] FAIL — Independent backup freshness alarm fires after missing a scheduled run;
  TLS expiration alarms tested through deploy/watch.py with separate read-only off-site
  credentials. Monitor-host dead-man provider configured manually; code is not delivery proof.
- [ ] PASS / [ ] FAIL — Cash-only, active cash shifts, manager controls and zero cashier discount
  threshold verified for every active business by pos:business-settings-check.
- [ ] PASS / [ ] FAIL — Lost-device command revokes token; captured old token immediately gets 401;
  other device works, audit remains append-only, unsynced orders preserved for recovery.
- [ ] PASS / [ ] FAIL — Code activation/rollback tested on staging, with reviewed schema compatibility,
  valid matching backup receipt and no financial down-migrations or live DB overwrite.
- [ ] PASS / [ ] FAIL — Signing guard passes and real signed release metadata matches approved build.

## Lost-device drill (isolated staging account/device)

1. Record a staging user's ID and installation UUID from its authorized session
   inventory; do not paste its bearer token in a ticket or shell history. Prove
   the staging tablet can call its own authenticated sessions endpoint.
2. On the approved backend shell run:
   `php artisan pos:revoke-device USER_ID INSTALLATION_UUID --reason=INC-DRILL`.
   Replace the two identifiers with the selected staging values. This deletes
   only tokens matching that user's exact installation and appends an audit event.
3. Retry the captured token through a secure test client: the next API request
   must be 401. Peer device remains authorized. PilotOperationsTest automates this
   with real Sanctum tokens, not Sanctum::actingAs.
4. For actual theft, revoke **all user installations/accounts used on that tablet**,
   rotate exposed passwords if needed and investigate audit/IP history. Revoking
   one cashier's device token does not revoke another user's token. A staff member
   knowing the password could sign in again; deactivate the account or reset the
   password when the incident warrants it. The existing manager session endpoint
   or own logout-all can revoke additional sessions.
5. OS-lock/MDM lock or wipe through an approved owner process. API revocation does
   not erase the stolen device or prevent offline cached access. Reconcile any
   unsynced orders before wiping a recovered device; never resend a cash payment
   blindly. Record incident, reconciliation and operator sign-off.

## Manual owner-only steps (not completed by code or CI)

- [ ] PASS / [ ] FAIL — Buy VPS/domain, select provider/region and approve recurring costs.
- [ ] PASS / [ ] FAIL — Name primary responsible operator, recovery deputy and on-call contact;
  record incident authority, maintenance hours and handoff.
- [ ] PASS / [ ] FAIL — Create actual SSH/DB/off-site/Telegram credentials privately, verify independent
  console access and restrict firewall/fail2ban on the chosen host.
- [ ] PASS / [ ] FAIL — Create permanent signing key on trusted owner computer, choose app ID/channel,
  store encrypted recovery copy and verify fingerprint (see android-release-signing.md).
- [ ] PASS / [ ] FAIL — Generate recovery identity off-server, retain **two independent copies outside
  application server**, distribute only public age recipient to backup host, test retrieval.
- [ ] PASS / [ ] FAIL — Approve cash/discount/refund/void/shift policies, customer/staff privacy notice,
  retention/deletion, accounting records and actual backup RPO/RTO acceptance.
- [ ] PASS / [ ] FAIL — Configure actual off-site immutability/lifecycle, independent monitor and Telegram
  recipient; acknowledge real alert delivery and timed restore report.
- [ ] PASS / [ ] FAIL — Accept real tablet OS lock, upgrade, offline recovery and lost-device drill.
- [ ] PASS / [ ] FAIL — Accept physical English/Khmer printer COPY, paper width/totals/cut/feed/reconnect;
  simulation does not prove the previously garbled physical receipt is fixed.
- [ ] PASS / [ ] FAIL — Authorize restricted pilot branch, training, rollback and escalation; then separately
  approve merge/deployment. Approval is not provided by this document.

Owner: __________  Operator: __________  Recovery deputy: __________
Commit/build/certificate: __________  Evidence/date: __________
Pilot approved: [ ] YES [ ] NO (all blockers must be resolved first)
