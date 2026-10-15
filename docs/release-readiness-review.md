# Release-readiness review and handoff — 15 October 2026

Reviewed baseline: `99f45632716b1a467b9bc57636f78c44bbdf18ad`, draft
[PR #11](https://github.com/sticky268/Top-Coffee-POS/pull/11). The owner authorized
remote review and verified fixes while away from the PC and printer. The running
port 8001 backend, main database, existing rehearsal database and local Windows
edits are outside this work. No merge, deployment or production migration is
authorized by this review. Kitchen-display removal remains intentional.

## Verified findings and changes

| Finding | Result | Regression evidence |
|---|---|---|
| The backend accepted any `APP_URL` whose parsed scheme was HTTPS, including localhost or embedded credentials. | Require a usable HTTPS host, reject credentials/query/fragment, loopback, unspecified addresses and the emulator host. The check reports booleans and never echoes embedded credentials. | `ProductionReadinessTest` exercises malformed, local, IPv4/IPv6 and valid deployment URLs; `ProductionCheckTest` verifies command wiring and redaction. |
| Readiness equated the MySQL driver with transactional tables. MyISAM can bypass rollback and row-lock assumptions even on a MySQL connection. | Inspect base-table engines in the configured MySQL/MariaDB schema and fail if any is not InnoDB. Never convert a table or repair data. | `ProductionDatabaseEngineTest` verifies the existing disposable InnoDB schema, creates an isolated MyISAM probe, verifies failure and read-only queries, then removes only that test probe. |
| The release document led with acceptance of an older candidate and the USB build's README still described a drawer test. | Label old acceptance as historical, add a current evidence boundary, and make test-build instructions start with an existing paid receipt's COPY. | Documentation and artifact-source review; final build checks verify the isolated package identity and visible label. |

The Flutter entry point already forces production URL validation in release mode,
even without a `FLAVOR=prod` define. Android release tasks already reject missing
signing configuration and the placeholder application ID. The existing backup
helper refuses source/populated-target overwrite and unsafe asset archive paths.
No replacement financial, offline, stock or payment logic was introduced.

## Automated evidence

The reviewed baseline's [POS validation](https://github.com/sticky268/Top-Coffee-POS/actions/runs/38730777195)
and [Android workflow](https://github.com/sticky268/Top-Coffee-POS/actions/runs/38730777222)
passed. They cover backend tests, real MySQL contention and populated migration
upgrade/rollback/reapplication, controlled backup/restore, Flutter analysis/tests,
report readers, 277 native writer assertions, SDK dispatch, debug APK builds,
isolated test identity, cashier/shift-close and device-local queue recovery.
The real native/SDK printer capture received 312,126 bytes, 4,300 rows, 180 valid
raster bands and one final cut, using synthetic data on emulator loopback.

The follow-up adds the production URL and real MySQL engine regressions to CI.
Use PR #11's final commit checks for the outcome of those changes. Earlier green
checks are historical evidence for their named source; no CI database is the
owner's target environment. Actual MySQL is tested; another deployment engine
must be rehearsed in its own intended environment.

## What remains before release

| Area | Status and required evidence | Access needed |
|---|---|---|
| Receipt acceptance | Latest native transport is automated-tested; actual paper/Khmer output is pending. Start with **Reprint COPY of an existing paid order**, inspect width, content and cut, and confirm no new sale or drawer pulse. | Owner's Android device and XP-N160II |
| Cashier-device acceptance | Verify the final build's actual offline force-stop/reopen, scoped recovery, keyboard/scanner and sharing behavior. Run one focused check at a time with rehearsal data. | Owner's PC/device; scanner if used |
| Hosting and connectivity | Choose the host/operator and permanent HTTPS API URL; verify the cashier device reaches it independently of USB and the development PC. Run the read-only production check there. | Chosen target environment |
| Signing and installation | Choose the permanent package/signing identity, retain private recovery material, verify the signed release package, and preserve/reconcile existing device queues before updates. CI USB/debug packages are rehearsal artifacts. | Owner's private signing/device setup |
| Migration and recovery | Restore a fresh target-environment backup into a separate matching database, rehearse the complete candidate migration set, compare records/totals and retain measured restore evidence. Existing CI rehearsals do not certify a future host or the running owner database. | Approved isolated staging environment |
| Monitoring and ownership | Choose the actual destination/responsible operator and verify alert delivery, backup failures and queue-exception recovery. No account or recipient was invented or contacted. | Operator's monitoring setup |

The next owner-side check is the physical receipt COPY only. Other rows remain
tracked for later, separate acceptance; the owner does not need to run commands
while away. Consult [production release and recovery](production-readiness.md)
for the approved-release sequence. PR #11 stays draft and unmerged until explicit
approval, with deployment approval treated separately.
