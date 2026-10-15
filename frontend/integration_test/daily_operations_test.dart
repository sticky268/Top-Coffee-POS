import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/main.dart' as app;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(
    finder,
    findsWidgets,
    reason: 'Timed out waiting for the next workflow screen',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cashier signs in, opens a shift, sells a drink and reconciles cash',
    (tester) async {
      app.main();
      await waitFor(tester, find.widgetWithText(TextFormField, 'Email'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        const String.fromEnvironment(
          'TEST_EMAIL',
          defaultValue: 'cashier@ci.invalid',
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        const String.fromEnvironment(
          'TEST_PASSWORD',
          defaultValue: 'ci-disposable-password',
        ),
      );
      await tester.tap(find.text('Sign in').last);
      await waitFor(tester, find.text('Cashier workspace'));
      await waitFor(tester, find.text('Open your shift'));
      await tester.tap(find.text('Open your shift'));
      await waitFor(tester, find.widgetWithText(FilledButton, 'Open shift'));
      await tester.tap(find.text('Open shift').last);
      await waitFor(tester, find.widgetWithText(TextFormField, 'Opening cash'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Opening cash'),
        '20',
      );
      await tester.tap(find.text('Confirm'));
      await waitFor(tester, find.text('Close shift'));
      await tester.tap(find.byTooltip('New takeaway order'));
      await waitFor(tester, find.text('CI Latte'));
      await tester.tap(find.text('CI Latte').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Review Order').last);
      await tester.tap(find.text('Review Order').last);
      await waitFor(tester, find.text('Takeaway order'));
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Amount received'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('checkout-review-scroll')),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount received'),
        '5',
      );
      await tester.scrollUntilVisible(
        find.text('Complete Sale'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('checkout-review-scroll')),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(find.text('Complete Sale'));
      await waitFor(tester, find.text('Payment Successful'));
      await tester.ensureVisible(find.text('Back to Dashboard'));
      await tester.tap(find.text('Back to Dashboard'));
      await waitFor(tester, find.text('Cashier workspace'));
      await waitFor(tester, find.textContaining(' is open'));
      await tester.tap(find.textContaining(' is open'));
      await waitFor(tester, find.text('Close shift'));
      // Wait for the local pending-order journal to confirm it is empty.
      for (var i = 0; i < 30; i++) {
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Close shift'),
        );
        if (button.onPressed != null) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.text('Close shift'));
      await waitFor(tester, find.widgetWithText(TextFormField, 'Counted cash'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Counted cash'),
        '23.50',
      );
      await tester.tap(find.text('Confirm'));
      await waitFor(tester, find.text('Awaiting manager review'));
      expect(find.text('Counted cash'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
