import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/auth/presentation/manager_pin_prompt.dart';

void main() {
  testWidgets('PIN is obscured, validated, returned once and blank on reopening', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await showDialog<String>(context: context, builder: (_) => const ManagerPinPrompt(action: 'Approve refund', manager: 'Mara'));
      }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.obscureText, isTrue);
    expect(input.enableSuggestions, isFalse);
    expect(input.autofillHints, isNull);
    await tester.enterText(field, '123');
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 6–12 digits.'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(field, '836492');
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(result, '836492');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN approval fits a narrow screen at large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
      child: const Scaffold(body: ManagerPinPrompt(action: 'Approve order cancellation', manager: 'Mara')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
