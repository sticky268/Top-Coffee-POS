import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/offline/journal_cipher.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/offline/pending_orders_screen.dart';
import 'package:top_coffee_pos/core/routing/app_router.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/application/auth_state.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/main.dart' as app;

import 'daily_operations_test.dart' show waitFor;

// Four separate Android processes, orchestrated by the CI-only host runner.
// No provider overrides, HTTP adapter fakes, token injection or API test routes.
const _phase = String.fromEnvironment('OFFLINE_PHASE');
const _witnessKey = 'ci-rehearsal:offline-snapshot';
const _password = 'ci-disposable-password';
const _stable = 'CI Offline Stable Latte';
const _changed = 'CI Offline Changed Latte';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  final messenger = ScaffoldMessenger.maybeOf(tester.element(finder));
  messenger?.clearSnackBars();
  messenger?.removeCurrentSnackBar();
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _fill(WidgetTester tester, String label, String value) async {
  final finder = find.widgetWithText(TextFormField, label);
  await waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<AuthenticatedUser> _authenticated(
    WidgetTester tester, ProviderContainer container, String email) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    final auth = container.read(authControllerProvider);
    if (auth is AuthAuthenticated &&
        auth.user.email == email &&
        container.read(currentBranchProvider) != null) {
      return auth.user;
    }
  }
  fail('The expected synthetic operator/session did not restore.');
}

Future<AuthenticatedUser> _login(
    WidgetTester tester, ProviderContainer container, String email) async {
  await container.read(authControllerProvider.notifier).logout();
  await _fill(tester, 'Email', email);
  await _fill(tester, 'Password', _password);
  await waitFor(tester, find.text('Sign in'));
  await _tap(tester, find.text('Sign in').last);
  return _authenticated(tester, container, email);
}

Future<List<PendingOrder>> _orders(ProviderContainer container) {
  final scope = container.read(orderScopeProvider)!;
  return container.read(orderOutboxProvider).list(scope.userId, scope.branchId);
}

Map<String, dynamic> _intent(PendingOrder order) => {
      'uuid': order.uuid,
      'user_id': order.userId,
      'branch_id': order.branchId,
      'payload': order.payload,
      'endpoint': order.endpoint,
      'created_at': order.createdAt.toIso8601String(),
      'fingerprint': order.fingerprint,
    };

Future<void> _pending(WidgetTester tester, ProviderContainer container) async {
  container.read(appRouterProvider).go('/pending-orders');
  await waitFor(tester, find.text('Pending Orders'));
}

Future<void> _showPendingText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 250,
      scrollable: find
          .descendant(
            of: find.byType(PendingOrdersScreen),
            matching: find.byType(Scrollable),
          )
          .first);
  await waitFor(tester, find.text(text));
}

Future<void> _queueSale(
    WidgetTester tester, ProviderContainer container, String product) async {
  container.read(appRouterProvider).go('/pos');
  await waitFor(tester, find.text(product));
  expect(container.read(cachedCatalogProvider), isTrue);
  await _tap(tester, find.text(product).first);
  await waitFor(tester, find.text('Review Order'));
  await _tap(tester, find.text('Review Order').last);
  await waitFor(tester, find.text('Takeaway order'));
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('checkout-review-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Amount received'), 200,
      scrollable: scroll);
  await tester.enterText(
      find.widgetWithText(TextField, 'Amount received'), '5');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.scrollUntilVisible(find.text('Complete Sale'), 200,
      scrollable: scroll);
  await _tap(tester, find.text('Complete Sale'));
  await waitFor(tester, find.text('Order saved on this device'));
  expect(find.text('Payment Successful'), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline sale recovery: $_phase', (tester) async {
    expect(Env.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');
    expect(['prepare', 'queue', 'restart', 'recover'], contains(_phase));
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TopCoffeeApp)),
        listen: false);
    final store = container.read(localStoreProvider);

    if (_phase == 'prepare') {
      final user = await _login(tester, container, 'offline-a@ci.invalid');
      expect(user.requireCashShift, isTrue);
      expect(user.allowedPaymentMethods, ['cash']);
      expect(container.read(currentBranchProvider)!.name, 'CI Offline A');
      await waitFor(tester, find.text('Open your shift'));
      await _tap(tester, find.text('Open your shift'));
      await waitFor(tester, find.widgetWithText(FilledButton, 'Open shift'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Open shift'));
      await _fill(tester, 'Opening cash', '20');
      await _tap(tester, find.text('Confirm'));
      await waitFor(tester, find.text('Close shift'));
      final branch = container.read(currentBranchProvider)!.id;
      expect(await store.read('active-shift:${user.id}:$branch'), isNotNull);
      container.read(appRouterProvider).go('/pos');
      await waitFor(tester, find.text(_stable));
      await waitFor(tester, find.text(_changed));
      expect(container.read(cachedCatalogProvider), isFalse);
      expect(await _orders(container), isEmpty);
    } else {
      // No login in these new processes: restore the real encrypted device
      // session, cached catalog, verified shift and original journal.
      final user =
          await _authenticated(tester, container, 'offline-a@ci.invalid');
      final home = user.branches.singleWhere((b) => b.name == 'CI Offline A');
      final other = user.branches.singleWhere((b) => b.name == 'CI Offline B');
      expect(container.read(currentBranchProvider)!.id, home.id);
      if (_phase == 'queue') {
        await _queueSale(tester, container, _stable);
        await _queueSale(tester, container, _changed);
        final saved = await _orders(container);
        expect(saved, hasLength(2));
        expect(saved.map((o) => o.uuid).toSet(), hasLength(2));
        for (final order in saved) {
          expect(order.status, 'pending');
          expect(order.orderId, isNull);
          expect(order.payload['shift_id'], isNotNull);
          expect(order.payload['expected_total'], 3.5);
          expect(order.payload['expected_cashier_id'], user.id);
        }
        await store.write(_witnessKey, jsonEncode(saved.map(_intent).toList()));
        // Exercise the same branch action as BranchContextBar, offline.
        container.read(currentBranchProvider.notifier).selectBranch(other);
        await tester.pump();
        await _pending(tester, container);
        await waitFor(tester,
            find.text('No orders saved on this device for this branch.'));
        await container.read(orderSyncProvider).sync();
        expect(await _orders(container), isEmpty);
        expect(
            (await container.read(orderOutboxProvider).list(user.id, home.id))
                .map(_intent)
                .toList(),
            saved.map(_intent).toList());
        container.read(currentBranchProvider.notifier).selectBranch(home);
        await tester.pump();
        await waitFor(tester, find.text('2 waiting for server confirmation'));
      } else {
        final original = jsonDecode((await store.read(_witnessKey))!) as List;
        if (_phase == 'restart') {
          final restored = await _orders(container);
          expect(restored.map(_intent).toList(), original);
          expect(restored.every((o) => o.status == 'pending'), isTrue);
          await _pending(tester, container);
          await waitFor(tester, find.text('2 waiting for server confirmation'));
          // Inspect raw SQLite values, not just the decrypting LocalStore API.
          final database = (store as SqliteLocalStore).database;
          final rows = await database
              .customSelect(
                  "SELECT value FROM offline_entries WHERE key LIKE 'order:%'")
              .get();
          expect(rows.length, greaterThanOrEqualTo(2));
          for (final row in rows) {
            final raw = row.read<String>('value');
            expect(raw.startsWith(JournalCipher.prefix), isTrue);
            for (final intent in original) {
              expect(raw, isNot(contains(intent['uuid'] as String)));
            }
          }
        } else {
          final api = container.read(apiClientProvider).dio;
          await container.read(orderSyncProvider).sync();
          var saved = await _orders(container);
          expect(saved.map(_intent).toList(), original);
          expect(saved.where((o) => o.status == 'synced'), hasLength(1));
          expect(saved.where((o) => o.status == 'review'), hasLength(1));
          final accepted = saved.singleWhere((o) => o.status == 'synced');
          final conflict = saved.singleWhere((o) => o.status == 'review');
          expect(conflict.error, contains('Prices have changed'));
          expect(conflict.orderId, isNull);
          expect(conflict.payload['expected_total'], 3.5);
          final requests = <Map<String, dynamic>>[];
          final recorder = InterceptorsWrapper(onRequest: (options, handler) {
            if (options.path == '/orders' && options.method == 'POST') {
              requests.add(Map<String, dynamic>.from(options.data as Map));
            }
            handler.next(options);
          });
          api.interceptors.add(recorder);
          addTearDown(() => api.interceptors.remove(recorder));
          await _pending(tester, container);
          await _showPendingText(tester, 'Confirmed by server');
          await _showPendingText(tester, 'Needs review');
          for (var i = 0; i < 2; i++) {
            await _tap(tester, find.text('Sync now'));
            await waitFor(tester, find.text('Sync now'));
          }
          expect(requests, isEmpty,
              reason: 'Bulk sync must not resend confirmed/review orders.');
          // Replay the exact persisted UUID/payload twice over real HTTP.
          // The host separately proves one DB order/payment/stock deduction.
          for (var i = 0; i < 2; i++) {
            final replay =
                await api.post(accepted.endpoint, data: accepted.payload);
            expect(replay.data['data']['id'], accepted.orderId);
            expect(replay.data['data']['total'], 3.5);
          }
          expect(requests, [accepted.payload, accepted.payload]);
          await _tap(tester, find.text('Retry original request'));
          await waitFor(tester, find.text('Sync now'));
          expect(requests.last, conflict.payload);
          saved = await _orders(container);
          expect(saved.map(_intent).toList(), original);
          expect(saved.singleWhere((o) => o.uuid == conflict.uuid).status,
              'review');
          // Account B is authorized for the same branch, but cannot see or
          // submit the original cashier's intent using its own token.
          await _login(tester, container, 'offline-b@ci.invalid');
          await _pending(tester, container);
          await waitFor(tester,
              find.text('No orders saved on this device for this branch.'));
          await container.read(orderSyncProvider).sync();
          expect(await _orders(container), isEmpty);
          final denied = await api.post(conflict.endpoint,
              data: conflict.payload,
              options: Options(validateStatus: (status) => status == 409));
          expect(denied.statusCode, 409);
          expect(denied.data['message'],
              'Sign in as the cashier who saved this pending order.');
          await _login(tester, container, 'offline-a@ci.invalid');
          await _pending(tester, container);
          await _showPendingText(tester, 'Needs review');
          expect((await _orders(container)).map(_intent).toList(), original);
          final ingredients = await api
              .get('/ingredients', queryParameters: {'branch_id': home.id});
          expect((ingredients.data['data'] as List).single['current_stock'],
              '19.750');
          final financials = await api.get(
              '/orders/${accepted.orderId}/financials',
              queryParameters: {'branch_id': home.id});
          expect(financials.data['data']['paid'], 3.5);
          expect(financials.data['data']['payments'], hasLength(1));
        }
      }
    }
    expect(tester.takeException(), isNull);
    debugPrint('PASS: disposable offline rehearsal phase $_phase');
  });
}
