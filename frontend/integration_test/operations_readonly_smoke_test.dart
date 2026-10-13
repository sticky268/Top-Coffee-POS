import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
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

Future<void> waitForControl(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'The shift action did not finish.');
}

Future<void> rehearseShift(WidgetTester tester) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  expect(
    find.widgetWithText(FilledButton, 'Close shift'),
    findsNothing,
    reason: 'Refusing to interfere with an existing open shift.',
  );
  final open = find.widgetWithText(FilledButton, 'Open shift');
  expect(
    open,
    findsOneWidget,
    reason: 'This account needs permission to open a shift.',
  );
  await tester.ensureVisible(open);
  await tester.tap(open);
  final openingCash = find.widgetWithText(TextFormField, 'Opening cash');
  await waitForControl(tester, openingCash);
  await tester.enterText(openingCash, '20');
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  final close = find.widgetWithText(FilledButton, 'Close shift');
  await waitForControl(tester, close);
  final card = find.ancestor(of: close, matching: find.byType(Card)).first;
  final title = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((text) => text.data ?? '')
      .firstWhere(
        (text) => text.startsWith('Shift #') && text.endsWith(' · open'),
      );
  for (var i = 0; i < 200; i++) {
    if (tester.widget<FilledButton>(close).onPressed != null) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(
    tester.widget<FilledButton>(close).onPressed,
    isNotNull,
    reason: 'Saved orders or operations must be resolved before closing.',
  );
  await tester.ensureVisible(close);
  await tester.tap(close);
  final countedCash = find.widgetWithText(TextFormField, 'Counted cash');
  await waitForControl(tester, countedCash);
  await tester.enterText(countedCash, '20');
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  final closedTitle = find.text(title.replaceFirst(' · open', ' · closed'));
  await waitForControl(tester, closedTitle);
  final closedCard = find
      .ancestor(of: closedTitle, matching: find.byType(Card))
      .first;
  expect(
    find.descendant(
      of: closedCard,
      matching: find.text('Awaiting manager review'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: closedCard, matching: find.text('Difference')),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find
          .ancestor(
            of: find.descendant(
              of: closedCard,
              matching: find.text('Difference'),
            ),
            matching: find.byType(Wrap),
          )
          .first,
      matching: find.text('\$0.00'),
    ),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
  debugPrint('PASS: $title closed with 20.00 counted and zero difference.');
}

Future<void> rehearseReview(WidgetTester tester) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OperationsScreen)),
  );
  expect(
    container.read(currentBranchProvider)?.id,
    21,
    reason: 'Review is restricted to rehearsal branch 21.',
  );
  const shiftId = int.fromEnvironment('REVIEW_SHIFT_ID');
  expect(shiftId, greaterThan(0), reason: 'Specify the rehearsal shift ID.');
  final title = find.text('Shift #$shiftId · closed');
  expect(title, findsOneWidget, reason: 'The target shift must be closed.');
  Finder card() => find.ancestor(of: title, matching: find.byType(Card)).first;
  void expectCash(String label, String value) {
    final row = find
        .ancestor(
          of: find.descendant(of: card(), matching: find.text(label)),
          matching: find.byType(Wrap),
        )
        .first;
    expect(
      find.descendant(of: row, matching: find.text(value)),
      findsOneWidget,
    );
  }

  expectCash('Opening cash', '\$20.00');
  expectCash('Expected drawer cash', '\$20.00');
  expectCash('Counted cash', '\$20.00');
  expectCash('Difference', '\$0.00');
  final reviewed = find.descendant(of: card(), matching: find.text('Reviewed'));
  if (reviewed.evaluate().isEmpty) {
    expect(
      find.descendant(
        of: card(),
        matching: find.text('Awaiting manager review'),
      ),
      findsOneWidget,
    );
    final review = find.descendant(
      of: card(),
      matching: find.widgetWithText(OutlinedButton, 'Confirm review'),
    );
    expect(
      review,
      findsOneWidget,
      reason: 'This account needs reports.view permission.',
    );
    await tester.ensureVisible(review);
    await tester.tap(review);
    await waitForControl(tester, find.text('Review shift'));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await waitForControl(tester, reviewed);
  }
  await tester.tap(find.byTooltip('Refresh'));
  await tester.pump();
  await waitForOperations(tester);
  expect(
    reviewed,
    findsOneWidget,
    reason: 'Review must persist after API refresh.',
  );
  expect(
    find.descendant(of: card(), matching: find.text('Awaiting manager review')),
    findsNothing,
  );
  expect(tester.takeException(), isNull);
  debugPrint('PASS: Shift #$shiftId manager review persisted after refresh.');
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
    expect(
      const bool.fromEnvironment('REHEARSE_SHIFT') &&
          const bool.fromEnvironment('REHEARSE_REVIEW'),
      isFalse,
      reason: 'Run shift creation and existing shift review separately.',
    );
    if (const bool.fromEnvironment('REHEARSE_REVIEW')) {
      await rehearseReview(tester);
    }
    if (const bool.fromEnvironment('REHEARSE_SHIFT')) {
      await rehearseShift(tester);
    }
  });
}
