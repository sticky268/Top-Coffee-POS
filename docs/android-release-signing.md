# Owner-controlled Android signing and release acceptance

Permanent application ID, signing identity and distribution channel are owner
decisions. Do not replace a tablet build while its offline queue is pending; an
uninstall can permanently destroy device-only orders. Debug USB rehearsal APKs
are not production releases. No permanent signing key is created by this PR.

## Create and protect the key on the owner's trusted build computer

Choose a permanent reverse-domain application ID you control and a private key
alias. Outside the repository, in an owner-only encrypted directory, run:

```sh
keytool -genkeypair -v -keystore /secure-signing/top-coffee-release.jks -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 -alias top-coffee-release
```

This interactively creates the real private signing key and certificate. Supply
real passwords only at the prompts; never add passwords to shell arguments,
chat, source or CI logs. On Windows use the actual encrypted drive path instead
of /secure-signing. Keep an encrypted offline recovery copy and passwords in an
independent owner vault; record certificate SHA-256 and the deputy custodian.
If using Google Play App Signing, follow its enrollment/export policy and keep
upload-key and app-signing-key responsibilities distinct. Never invent keys.

Create frontend/android/key.properties privately (never commit it), with real
storePassword, keyPassword, keyAlias and storeFile properties. storeFile is an
absolute path to that external key, or resolves relative to frontend/android.
Windows Java properties paths should use forward slashes or escaped backslashes.
Set mode 600 on Unix or owner-only NTFS ACLs on Windows. Do not put passwords in
Gradle commands or environment dumps. Configure permanent POS_APPLICATION_ID in
private Gradle user properties, not the sample com.example identity.

```sh
git check-ignore frontend/android/key.properties
python3 deploy/check_signing_files.py
```

The first confirms the private properties file is ignored. The second scans
**tracked** paths/content and fails for keystores, key.properties, common private
key PEM or JKS/JCEKS magic even under another name. .gitignore covers *.jks,
*.keystore, *.p12 and *.pfx at any depth. This guard is an accidental-commit check,
not a general secret scanner. If a key was ever committed, ignoring it later is
insufficient: stop release, investigate exposure and rotate through the actual
distribution provider's supported process. Never casually replace an existing
production signing identity.

## Build a real release after backend readiness passes

From frontend, with production URL and permanent ID privately configured:

```sh
flutter pub get
flutter test
flutter build apk --release --obfuscate --split-debug-info=/secure-signing/top-coffee-symbols --dart-define=FLAVOR=prod --dart-define=API_BASE_URL=https://api.example.invalid/api/v1
```

The first resolves the reviewed lock, the second runs tests, and the third signs
an obfuscated release while saving crash symbols outside Git. Replace the
reserved URL with the approved HTTPS API before building; no real domain is
invented. Confirm versionCode increases over installed releases. Archive the
exact reviewed SHA, lock, build tools, symbols and certificate fingerprint in
restricted release records. Native shrinking follows the Flutter/AGP release
toolchain; do not claim obfuscation hides embedded secrets or prevents device
extraction. No API/provider/payment secret belongs in Dart defines or the APK.

Use the installed Android SDK build-tools paths:

```sh
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
aapt dump xmltree build/app/outputs/flutter-apk/app-release.apk AndroidManifest.xml
```

These verify signature/certificate, inspect package/version/SDK metadata and
inspect merged manifest flags. Check debuggable=false/absent, allowBackup=false,
cleartext disabled and expected network security policy. Preserve existing
release screenshot protection and OS lock; obfuscation is not a substitute.

## Release pass/fail record (owner must fill)

- [ ] PASS / [ ] FAIL — Permanent ID, alias, channel and versionCode approved.
- [ ] PASS / [ ] FAIL — External key/vault recovery copy restored and fingerprint matches.
- [ ] PASS / [ ] FAIL — Git ignore and signing guard pass; no real secret in bundle/log.
- [ ] PASS / [ ] FAIL — APK signature, manifest and exact SHA independently checked.
- [ ] PASS / [ ] FAIL — Upgrade tested without clearing encrypted offline queues.
- [ ] PASS / [ ] FAIL — Real tablet auto-lock, screenshot/backup and lost-device drill accepted.
- [ ] PASS / [ ] FAIL — English/Khmer receipt COPY, money, width/feed/cut and reconnect tested on actual printer.
- [ ] PASS / [ ] FAIL — Backend readiness gates pass, distribution/rollback and named operator approved.

Signing or a simulated printer test alone is not physical acceptance. See the
[Flutter Android release guide](https://docs.flutter.dev/deployment/android).
