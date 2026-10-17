# iOS setup, signing and acceptance

This is preparation, not release approval. The application changes are merged.
CI compile success does not certify signing, an installed application, physical
hardware, backend readiness or App Store acceptance. Never store Apple passwords,
private keys, provisioning secrets or real customer data in repository evidence.

## Mac setup

Use a clean checkout of the exact candidate. Preserve existing checkouts and
reconcile pending device orders before changing identity, uninstalling or updating.
Install Flutter 3.44.9 to match CI, a compatible Xcode and its iOS SDK/runtime.
For App Store uploads as of October 2026, Apple requires Xcode 26 or later and
the iOS 26 SDK or later. The iOS 13 deployment target is a separate minimum
runtime setting, not an SDK selection. Verify dependencies' minimum OS versions.

If necessary, select the installed Xcode path and run first-launch setup:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license
xcodebuild -downloadPlatform iOS
```

Review licences yourself. Install CocoaPods if Flutter reports it is required
for plugin fallback. The project also references Flutter's generated Swift
package; do not hand-edit ephemeral package contents or Generated.xcconfig.

From the repository root:

```sh
git rev-parse HEAD
git status --short
xcodebuild -version
flutter --version
flutter doctor -v
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator --debug
open ios/Runner.xcworkspace
flutter devices
```

Start Device Hub on Xcode 27, or Simulator on earlier Xcode. Then use the
actual listed simulator ID and approved staging HTTPS endpoint:

```sh
flutter run -d <simulator-id> --dart-define=API_BASE_URL=https://<staging-host>/api/v1
```

The default 10.0.2.2 address is Android-only. Simulator localhost refers to the
Mac; a Windows backend needs its reachable address. Physical-device localhost
refers to the phone. Use trusted HTTPS; Info.plist has no custom HTTP exceptions.
Do not broaden App Transport Security to work around a production URL problem.

## Owner identity and signing inputs

In Xcode open Runner.xcworkspace, select the Runner target, and use Signing &
Capabilities. The owner supplies the permanent unique bundle ID, Apple team,
approved display name/icon, version/build and required capabilities. Keep the
same permanent application ID across updates. Check Debug, Release and Profile;
also align RunnerTests with the selected identity.

Current checked-in identities are com.example.topCoffeePos and
com.example.topCoffeePos.RunnerTests. No development team is configured.
The explicit Automatic settings in project.pbxproj belong to RunnerTests;
Runner's signing UI/effective settings must be verified independently.
Legacy iPhone Developer identity entries do not prove valid provisioning.

For development, add the owner's Apple account, select the team and resolve
development certificate/private-key and provisioning access. Connect an unlocked
iPhone/iPad, trust the Mac and enable Developer Mode if required. Run on the
actual device ID. A free personal team may support development testing; store
distribution needs Apple Developer Program enrollment and appropriate App Store
Connect permissions. Do not send passwords, certificates or keys in chat.

## Evidence and functional gates

The iOS workflow runs analysis, Flutter unit/widget tests, simulator Debug
compilation and unsigned device Release compilation. Its reserved example.invalid
API URL is compile-only. It never installs, signs, launches, archives for
distribution or uploads. result.json is produced only after all prior steps pass.
RunnerTests currently contains an empty example, not native acceptance tests.

The iOS AppDelegate currently registers plugins but has no implementation of
the application's top_coffee_pos/printer channel. Android printer/drawer code
and paper evidence do not certify iOS support. Before approving iOS cashier use,
implement and validate the intended transport on iOS or explicitly approve a
scope without those features and make the UI match that scope. Do not mark
printing/drawer acceptance passed from compilation alone.

Record exact source/build, device/OS, operator, date, result and sanitized evidence:

- Simulator: launch, staging login, phone/tablet layout, themes and navigation.
- Physical signed device: HTTPS connectivity without a development tether,
  secure storage/session persistence, lock/background/resume and permissions.
- Staging cashier: totals/change, held orders, branch/account isolation,
  manager approval/refusal/lockout and receipt/export sharing.
- Offline: warm catalog, disconnect API, queue sale, terminate/reopen, preserve
  original UUID, switch branch/user, reconnect and prove exactly one
  order/payment/stock effect; retain conflicts for review.
- Upgrade: retain pending queues and credentials under the permanent identity;
  test storage/key failures without silently losing or resubmitting money.
- Physical printer/drawer: only after iOS support exists; English/Khmer COPY,
  totals/cut, disconnect/reconnect and uncertain output without another payment.

Use isolated staging data, never new production sales for acceptance. The current
integration host runner is Android/disposable-CI oriented; do not point it at a
real backend or claim it already runs on iOS.

## Clone troubleshooting and current evidence

The clean-checkout iOS run on source 40dfc636903b7bd1b7611469be555645c08836b4
passed analysis/tests, simulator Debug and unsigned device Release compilation:
https://github.com/sticky268/Top-Coffee-POS/actions/runs/38890001098 .
POS validation also passed:
https://github.com/sticky268/Top-Coffee-POS/actions/runs/38890001104 .
This is historical evidence for that source, not certification of later edits.

That source's Android integration run timed out after installing the offline
restart test, before reporting a test assertion:
https://github.com/sticky268/Top-Coffee-POS/actions/runs/38890001129 .
The root cause is unresolved. The runner now captures per-phase verbose Flutter
logs and failure logcat before emulator teardown, preserves no-uninstall behavior
and fails on timeout without retrying or clearing device data. Those diagnostics
are not a claim that the restart issue is fixed.

The iOS matrix now checks Flutter 3.44.9 and the owner's 3.47.7 independently.
Read each exact candidate's checks; do not infer either result from an older run.

Catalog image selection uses image_picker with gallery access. Info.plist now
declares NSPhotoLibraryUsageDescription, as required by the plugin's iOS setup.
Test allow/deny/cancel and product-photo selection on the real device; compilation
does not certify permission behavior. No camera or microphone flow was added.

For a local signing failure, errSecInternalComponent is not a package
deprecation warning. Confirm the intended identity/private key exists in the
login keychain, unlock it privately and allow only the signing tool access.
Never delete/recreate keys or reset certificate trust as a first step.
Do not upload keychain passwords, keys or certificates in a build log.

An installed Flutter Debug application on iOS must be started through Xcode or
Flutter tooling. A home-screen message about Debug launch restrictions is not a
backend connection diagnosis. For later standalone rehearsal, use a separately
authorized signed Profile build with the verified staging endpoint. Release
builds enforce the production HTTPS URL guard. Preserve all queued data.

## Distribution gate (owner-controlled, not executed)

Keep five evidence groups:
1. Exact candidate, green CI, Mac toolchain versions and compile/test evidence.
2. Approved identity/team/capabilities/version plus signed archive metadata.
3. Signed physical-device and update/offline acceptance, including resolved
   printer scope and explicit owner acceptance.
4. Approved HTTPS backend, migration/restore and operations readiness evidence.
5. Store record, screenshots, accurate privacy disclosures/SDK privacy manifests
   and required-reason APIs review, review access/instructions, export-compliance
   answers and explicit distribution authorization.

After these gates and separate authorization, the owner can register the explicit
App ID and matching App Store Connect application, then build locally:

```sh
flutter build ipa --release --build-name=<approved-version> --build-number=<unique-build> --dart-define=FLAVOR=prod --dart-define=API_BASE_URL=https://<production-host>/api/v1
```

Archives/export outputs are under build/ios/archive and build/ios/ipa.
Validate signing/entitlements and the archive in Xcode Organizer, then use
TestFlight for final release acceptance before an explicitly authorized store
submission. Apple processing/review is a further gate, not guaranteed by CI.
Do not run this command with placeholder identity or treat its presence as approval.

References:
- https://docs.flutter.dev/platform-integration/ios/setup
- https://docs.flutter.dev/deployment/ios
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- [Production readiness](production-readiness.md)
- [Pre-pilot acceptance](pre-pilot-checklist.md)

## Remote verification follow-up — 16 October 2026

Application source ffb3a33ee4693f003afc3e772c0b9e6a83c2e040 passed:
- [iOS matrix](https://github.com/sticky268/Top-Coffee-POS/actions/runs/38899029518):
  Flutter 3.44.9 and 3.47.7 each passed analysis, all 476 tests, simulator Debug
  compilation and unsigned device Release compilation.
- [POS validation](https://github.com/sticky268/Top-Coffee-POS/actions/runs/38899029614):
  backend, actual MySQL suites, Flutter tests and Android debug/native checks.
- Info.plist now explains local-server network access and product-photo/receipt-logo
  selection. It does not relax transport security or configure a backend endpoint.

[Android rehearsal](https://github.com/sticky268/Top-Coffee-POS/actions/runs/38899029571)
passed cashier, read-only operations, manager approval, offline prepare and queue
phases. Restart timed out with zero test cases started. Its log shows the VM
and DDS connected successfully, followed by a wait for the integration-test
service extension; device logcat contains no reported app crash. This does not
establish a cashier-data defect or certify offline restart/recovery.

The next controlled run uses Flutter 3.47.7 for the integration host, matching
one green iOS/toolchain baseline. This is a compatibility experiment, not a
claimed root-cause fix. No tests, data-preservation flags or ledger assertions
are removed. On timeout, read-only VM/isolate diagnostics are captured before
process cleanup, using only the matching loopback forward advertised by the
owned CI process. No objects or application variables are fetched.
Read the exact new run before treating this experiment as successful.

Owner Mac changes and installed development app are separate evidence. Physical
launch, backend connectivity, retained-queue updates, printer implementation/
acceptance and owner signing/distribution gates remain open.
