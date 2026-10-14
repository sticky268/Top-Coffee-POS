# Top Coffee POS

Flutter cashier/management application and Laravel API. The active backend is `backend-skeleton/`; `backend/` is the original scaffold and is not the production application.

## Features

Dine-in/takeaway checkout; table and held-order management; cash/card/QR/split payment records; receipts and electronic bills; products, variants and photos; recipes, ingredient stock, wastage and purchase history; staff, customers, loyalty and branches; reports, expenses, subscriptions and audit logs; coffee-themed light/dark UI. Kitchen Display was intentionally removed.

Card/QR are recorded payment methods. They do not imply integration with a payment gateway or terminal. Release acceptance must include whichever external payment process the business actually uses.

## Development

Install PHP 8.2+, Composer, Flutter 3.44.9 and Java 17 with Android SDK tooling. Run Composer installation in `backend-skeleton/`, copy its `.env.example` to a local `.env`, configure the development database/cache and generate a development application key. Migrate and seed only the development database. Start the Laravel API, then run `flutter pub get` and `flutter run` from `frontend/`.

The default Android emulator API URL is `http://10.0.2.2:8000/api/v1`. A different device/server needs an explicit `API_BASE_URL`. Production and release builds require the production HTTPS API URL. Configure Java through `JAVA_HOME`/Flutter's JDK settings rather than committing a path from one Windows machine.

Do not use demo accounts or generate a new application key in an existing production environment.

## Verification

- Backend: `php vendor/bin/phpunit` from `backend-skeleton/`. PHPUnit uses an isolated SQLite in-memory database and a test-only key.
- Frontend: `flutter analyze`, `flutter test`, and `flutter build apk --debug` from `frontend/`.
- GitHub Actions runs the full PHP and Flutter checks and Android debug build. This provides code/build evidence, not physical-printer or deployment certification.
- The authoritative phase scope and acceptance record is [docs/eight-phase-progress.md](docs/eight-phase-progress.md).
- Release configuration, database rehearsal, printer/device checks, backup recovery and deployment procedure are in [docs/production-readiness.md](docs/production-readiness.md).

## Offline operation

Checkout writes a durable request before transmitting it. Pending/review/confirmed requests are visible in Pending Orders. Network/time-out errors retain the exact original UUID and payload, so reconnecting or reopening can recover without recreating the sale. Sync runs only for the signed-in cashier and selected branch. Catalog snapshots expire after 24 hours, and protected cached sessions after 8 hours.

A pending request is **not a completed sale**. It does not print a paid receipt or appear in confirmed server sales until acknowledged. Price, stock, table, permission and subscription conflicts remain for review; never collect a second payment simply because confirmation is delayed. Do not uninstall or clear app data while requests remain unresolved.

## Release status

The feature branch is `feature/kitchen-order-updates`. PR #6 must stay unmerged until the owner explicitly approves. Signed release configuration, production migration/backup rehearsal and actual device/printer acceptance remain mandatory before launch. Do not describe implementation alone as completion of all eight phases.
