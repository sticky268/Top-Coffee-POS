import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/dashboard_screen.dart';
import 'package:top_coffee_pos/features/operations/presentation/operations_screen.dart';

Future<void> waitForHome(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(DashboardScreen).evaluate().isNotEmpty) return;
    if (find.widgetWithText(TextFormField, 'Email').evaluate().isNotEmpty) {
      if (const bool.fromEnvironment('SMOKE_CI_LOGIN')) {
        expect(Env.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'cashier@ci.invalid',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'ci-disposable-password',
        );
        await tester.tap(find.text('Sign in').last);
        continue;
      }
      fail(
        'No saved signed-in session. Sign in normally on this emulator, then rerun this test.',
      );
    }
  }
  fail(
    'The signed-in home screen did not load. Check the rehearsal API server.',
  );
}

Future<void> waitForOperations(WidgetTester tester) async {
  final refresh = find.descendant(
    of: find.byType(OperationsScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Refresh',
    ),
  );
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (refresh.evaluate().isNotEmpty &&
        tester.widget<IconButton>(refresh).onPressed != null) {
      expect(
        find.text('Could not load operations'),
        findsNothing,
        reason: 'The selected operations section returned a loading error.',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'The operations screen raised a rendering or runtime error.',
      );
      return;
    }
  }
  fail(
    'Daily Operations did not finish loading. Check the rehearsal API server.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('existing signed-in session loads accessible operations views', (
    tester,
  ) async {
    const expectedApi = String.fromEnvironment(
      'SMOKE_EXPECTED_API',
      defaultValue: 'http://10.0.2.2:8001/api/v1',
    );
    expect(
      Env.apiBaseUrl,
      expectedApi,
      reason: 'Use the explicit rehearsal API endpoint for this smoke test.',
    );
    expect(
      Uri.parse(expectedApi).host,
      '10.0.2.2',
      reason: 'This test is restricted to the Android emulator host.',
    );

    // Keep the real stored session, API repositories, routing and UI. Suppress
    // automatic outbox uploads so this inspection cannot submit saved sales.
    runApp(
      ProviderScope(
        overrides: [orderSyncWorkerProvider.overrideWith((ref) {})],
        child: const TopCoffeeApp(),
      ),
    );
    await waitForHome(tester);

    final navigation = find.widgetWithText(ListTile, 'Daily Operations');
    if (navigation.evaluate().isEmpty) {
      final drawer = find.byTooltip('Open navigation menu');
      expect(
        drawer,
        findsOneWidget,
        reason: 'Daily Operations must be reachable from the app navigation.',
      );
      await tester.tap(drawer);
      await tester.pumpAndSettle();
    }
    expect(navigation, findsOneWidget);
    final shell = Scaffold.maybeOf(tester.element(navigation));
    await tester.ensureVisible(navigation);
    await tester.tap(navigation);
    await waitForOperations(tester);
    await tester.pumpAndSettle();
    if (shell != null && shell.mounted) {
      expect(
        shell.isDrawerOpen,
        isFalse,
        reason:
            'Navigation must close the drawer so operations controls can be used.',
      );
    }
    expect(find.widgetWithText(ChoiceChip, 'Shifts'), findsOneWidget);
    expect(
      find.text('No shifts for this branch yet.').evaluate().isNotEmpty ||
          find.textContaining('Shift #').evaluate().isNotEmpty,
      isTrue,
      reason: 'Shift records or the empty state must be displayed.',
    );
    debugPrint('PASS: Shifts loaded without a rendering or API error.');

    for (final section in ['Stock counts', 'Availability', 'Owner report']) {
      final chip = find.widgetWithText(ChoiceChip, section);
      if (chip.evaluate().isEmpty) {
        continue; // Respect this account's permissions.
      }
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await waitForOperations(tester);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      debugPrint('PASS: $section loaded without a rendering or API error.');
    }
    final shifts = find.widgetWithText(ChoiceChip, 'Shifts');
    await tester.ensureVisible(shifts);
    await tester.tap(shifts);
    await waitForOperations(tester);
    expect(tester.takeException(), isNull);
  });
}
