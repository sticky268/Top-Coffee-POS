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
                  if (sent.length == 2) {
                    throw const UncertainOperationException('Restore access');
                  }
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
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(sent, [
      {'amount': 5},
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
  testWidgets('closing preview compares counted cash without changing payload', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOperationForm(
                context,
                title: 'Close shift',
                expectedCash: 20.10,
                fields: const [
                  OperationField('counted_cash', 'Counted cash', number: true),
                ],
                save: (values) async => sent = values,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Expected drawer cash (at refresh): \$20.10'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '20.09');
    await tester.pump();
    expect(find.text('\$0.01 short'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '20.10');
    await tester.pump();
    expect(find.text('Cash count matches'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '21.10');
    await tester.pump();
    expect(find.text('\$1.00 over'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(sent, {'counted_cash': 21.10});
    expect(tester.takeException(), isNull);
  });

  testWidgets('friendly option labels preserve the original submitted value', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOperationForm(
                context,
                title: 'Cash movement',
                fields: const [
                  OperationField(
                    'type',
                    'Direction',
                    options: ['in', 'out'],
                    optionLabels: {'in': 'Add cash', 'out': 'Remove cash'},
                  ),
                ],
                save: (values) async => sent = values,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Add cash'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove cash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(sent, {'type': 'out'});
    expect(tester.takeException(), isNull);
  });
}
