import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/routing/app_router.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/application/auth_state.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/main.dart' as app;
import 'package:uuid/uuid.dart';

import 'daily_operations_test.dart' show waitFor;

// Synthetic credentials for IntegrationFixtureSeeder only. Never owner PINs.
const _password = 'ci-disposable-password';
const _pin = '836492';
const _wrongPin = '928374';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
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

Future<void> _login(
    WidgetTester tester, ProviderContainer container, String email) async {
  await container.read(authControllerProvider.notifier).logout();
  await waitFor(tester, find.widgetWithText(TextFormField, 'Email'));
  await _fill(tester, 'Email', email);
  await _fill(tester, 'Password', _password);
  await _tap(tester, find.text('Sign in').last);
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (container.read(authControllerProvider) is AuthAuthenticated &&
        container.read(currentBranchProvider) != null) {
      return;
    }
  }
  fail('Synthetic manager login/branch initialization did not complete.');
}

Future<void> _enroll(WidgetTester tester, ProviderContainer container,
    {bool wrongPasswordFirst = false}) async {
  container.read(appRouterProvider).go('/settings');
  await waitFor(tester, find.text('Save manager PIN'));
  Future<void> submit(String password) async {
    await _fill(tester, 'Current account password', password);
    await _fill(tester, 'New manager PIN', _pin);
    await _fill(tester, 'Confirm manager PIN', _pin);
    await _tap(tester, find.text('Save manager PIN'));
  }

  if (wrongPasswordFirst) {
    await submit('wrong-disposable-password');
    await waitFor(tester, find.text('Manager verification failed.'));
  }
  await submit(_password);
  await waitFor(
      tester,
      find.text(
          'Manager PIN saved. Use it only with your own signed-in account.'));
  for (final label in [
    'Current account password',
    'New manager PIN',
    'Confirm manager PIN'
  ]) {
    expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, label))
            .controller!
            .text,
        isEmpty);
  }
  final status =
      await container.read(apiClientProvider).dio.get('/auth/manager-pin');
  expect(status.data['data']['configured'], isTrue);
  expect(status.data['data']['locked'], isFalse);
}

Future<void> _approve(WidgetTester tester, String pin) async {
  final input = find.byKey(const ValueKey('manager-pin-input'));
  await waitFor(tester, input);
  final text = tester.widget<TextField>(
      find.descendant(of: input, matching: find.byType(TextField)));
  expect(text.obscureText, isTrue);
  expect(text.enableSuggestions, isFalse);
  expect(text.autofillHints, isNull);
  expect(text.controller!.text, isEmpty);
  await tester.enterText(input, pin);
  FocusManager.instance.primaryFocus?.unfocus();
  await _tap(tester, find.text('Approve'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'manager enrolls, refunds, cancels both ways and cannot bypass account lockout',
      (tester) async {
    // Mutating integration acceptance must never target a shop/staging/live URL.
    expect(Env.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TopCoffeeApp)),
        listen: false);
    final api = container.read(apiClientProvider).dio;
    final refundUuids = <String>[];
    final cancelStatuses = <int>[];
    final recorder = InterceptorsWrapper(
      onRequest: (options, handler) {
        // Record nonsecret evidence only; never copy headers/tokens/PIN bodies.
        if (options.path.endsWith('/refund')) {
          refundUuids.add((options.data as Map)['uuid'] as String);
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (response.requestOptions.path.endsWith('/cancel')) {
          cancelStatuses.add(response.statusCode!);
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (error.requestOptions.path.endsWith('/cancel')) {
          cancelStatuses.add(error.response?.statusCode ?? 0);
        }
        handler.next(error);
      },
    );
    api.interceptors.add(recorder);
    addTearDown(() => api.interceptors.remove(recorder));
    await _login(tester, container, 'manager@ci.invalid');
    final auth = container.read(authControllerProvider) as AuthAuthenticated;
    expect(auth.user.requireManagerPin, isTrue);
    expect(container.read(currentBranchProvider)!.name, 'CI Manager Branch');
    final branch = container.read(currentBranchProvider)!.id;
    await _enroll(tester, container, wrongPasswordFirst: true);
    final products =
        await api.get('/products', queryParameters: {'branch_id': branch});
    final product = (products.data['data'] as List)
        .singleWhere((dynamic p) => p['name'] == 'CI Approval Latte')['id'];
    final tables =
        await api.get('/tables', queryParameters: {'branch_id': branch});
    final table = (tables.data['data'] as List)
        .singleWhere((dynamic t) => t['name'] == 'CI Approval Table')['id'];
    await api.post('/shifts', data: {
      'uuid': const Uuid().v4(),
      'branch_id': branch,
      'opening_cash': 20
    });
    final sale = await api.post('/orders', data: {
      'uuid': const Uuid().v4(),
      'branch_id': branch,
      'order_type': 'takeaway',
      'items': [
        {'product_id': product, 'quantity': 1}
      ],
      'payment': {'method': 'cash', 'tendered': 5},
    });
    final saleId = sale.data['data']['id'] as int;
    Future<Map<String, dynamic>> financials() async {
      final response = await api.get('/orders/$saleId/financials',
          queryParameters: {'branch_id': branch});
      return Map<String, dynamic>.from(response.data['data'] as Map);
    }

    container.read(appRouterProvider).go('/orders/$saleId/financials');
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Refund'));
    await _fill(tester, 'Amount', '1');
    await _fill(tester, 'Reason', 'CI manager approval correction');
    await _tap(tester, find.text('Confirm'));
    await waitFor(tester, find.byKey(const ValueKey('manager-pin-input')));
    await _tap(tester, find.text('Cancel').last);
    await waitFor(
        tester, find.text('Refund approval cancelled. No request was sent.'));
    expect(refundUuids, isEmpty);
    expect((await financials())['refunded'], 0);
    await _tap(tester, find.text('Confirm'));
    await _approve(tester, _wrongPin);
    await waitFor(tester, find.text('Manager verification failed.'));
    expect((await financials())['refunded'], 0);
    await _tap(tester, find.text('Confirm'));
    await _approve(tester, _pin);
    await waitFor(tester, find.text('Refunded: \$1.00'));
    final completed = await financials();
    expect(completed['refunded'], 1);
    expect(((completed['payments'] as List).single['refunds'] as List),
        hasLength(1));
    final pending = jsonEncode(
        await container.read(operationsRepositoryProvider).pending());
    for (final secret in [_pin, _wrongPin, _password]) {
      expect(pending, isNot(contains(secret)));
    }
    // Replay the UI's exact nonsecret intent/UUID through the real API with a
    // fresh PIN. A stored result must not create a second refund.
    await api.post('/orders/$saleId/refund',
        data: {
          'amount': 1,
          'inventory_disposition': 'consumed',
          'reason': 'CI manager approval correction',
          'branch_id': branch,
          'expected_user_id': auth.user.id,
          'uuid': refundUuids.last,
        },
        options: Options(headers: {'X-Manager-Pin': _pin}));
    expect((await financials())['refunded'], 1);

    Future<int> held() async {
      final response = await api.post('/orders/hold', data: {
        'uuid': const Uuid().v4(),
        'branch_id': branch,
        'order_type': 'dine_in',
        'table_id': table,
        'items': [
          {'product_id': product, 'quantity': 1}
        ],
      });
      return response.data['data']['id'] as int;
    }

    Future<String> status(int id) async {
      final response =
          await api.get('/orders/$id', queryParameters: {'branch_id': branch});
      return response.data['data']['status'] as String;
    }

    Future<void> cancel(String pin, {bool editor = false}) async {
      final before = cancelStatuses.length;
      final control = editor
          ? find.text('Cancel Order')
          : find.byTooltip('Cancel order');
      await waitFor(tester, control);
      final anchor = control.last;
      ScaffoldMessenger.of(tester.element(anchor)).clearSnackBars();
      await _tap(tester, anchor);
      await waitFor(tester, find.text('Cancel Order?'));
      await _tap(tester, find.text('Cancel Order').last);
      await _approve(tester, pin);
      for (var i = 0; i < 100 && cancelStatuses.length == before; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(cancelStatuses.length, before + 1);
      await tester.pump(const Duration(milliseconds: 300));
    }

    final firstHeld = await held();
    container.read(appRouterProvider).go('/orders/$firstHeld');
    await cancel(_wrongPin);
    expect(cancelStatuses.last, 403);
    await waitFor(tester, find.text('Manager verification failed.'));
    expect(await status(firstHeld), 'held');
    await cancel(_pin);
    expect(cancelStatuses.last, 200);
    expect(await status(firstHeld), 'cancelled');
    final secondHeld = await held();
    container.read(appRouterProvider).go('/pos/open-order/$secondHeld');
    await cancel(_wrongPin, editor: true);
    expect(cancelStatuses.last, 403);
    await waitFor(tester, find.text('Manager verification failed.'));
    expect(await status(secondHeld), 'held');
    await cancel(_pin, editor: true);
    expect(cancelStatuses.last, 200);
    expect(await status(secondHeld), 'cancelled');
    final released =
        await api.get('/tables', queryParameters: {'branch_id': branch});
    expect(
        (released.data['data'] as List)
            .singleWhere((dynamic t) => t['id'] == table)['status'],
        'available');

    await _login(tester, container, 'locked-manager@ci.invalid');
    await _enroll(tester, container);
    final lockedHeld = await held();
    container.read(appRouterProvider).go('/orders/$lockedHeld');
    for (var i = 0; i < 5; i++) {
      await cancel(_wrongPin);
      expect(cancelStatuses.last, i == 4 ? 429 : 403);
    }
    await waitFor(tester, find.text('Manager PIN locked for 15 minutes.'));
    await cancel(_pin);
    expect(cancelStatuses.last, 429);
    await waitFor(
        tester,
        find.text(
            'Manager PIN is temporarily locked. Wait 15 minutes from the last lockout.'));
    expect(await status(lockedHeld), 'held');
    final locked = await api.get('/auth/manager-pin');
    expect(locked.data['data']['locked'], isTrue);
    container.read(appRouterProvider).go('/settings');
    await _fill(tester, 'Current account password', _password);
    await _fill(tester, 'New manager PIN', _pin);
    await _fill(tester, 'Confirm manager PIN', _pin);
    await _tap(tester, find.text('Save manager PIN'));
    await waitFor(
        tester,
        find.text(
            'Manager PIN is temporarily locked. Wait 15 minutes from the last lockout.'));
    expect((await api.get('/auth/manager-pin')).data['data']['locked'], isTrue);
    expect(tester.takeException(), isNull);
    // No printer, cash drawer, external payment, production key or live server.
    debugPrint(
        'PASS: real manager Settings enrollment, masked refund/cancel prompts, one refund replay, both held-order cancellations and persistent account lockout. Synthetic disposable API only.');
  });
}
