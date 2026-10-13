import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/operations/presentation/operation_form.dart';

void main() {
  testWidgets('an uncertain response retains the original amount for retry', (
    tester,
  ) async {
    final sent = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOperationForm(
                context,
                title: 'Refund',
                fields: const [
                  OperationField('amount', 'Amount', number: true),
                ],
                save: (values) async {
                  sent.add(Map.of(values));
                  if (sent.length == 1) throw const NetworkException();
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '5');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(sent, [
      {'amount': 5},
      {'amount': 5},
    ]);
    expect(find.text('Refund'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel safely disposes controllers after the dialog closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOperationForm(
                context,
                title: 'Count',
                fields: const [OperationField('reason', 'Reason')],
                save: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Weekly count');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
