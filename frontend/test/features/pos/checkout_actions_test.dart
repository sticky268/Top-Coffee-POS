import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/checkout_actions.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(800, 1280), const Size(360, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('checkout actions fit $size at text scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Column(children: [
            const Expanded(child: SingleChildScrollView(child: SizedBox(height: 1800))),
            CheckoutActions(totalLabel: '\$125.25', enabled: true,
              isSubmitting: false, onComplete: (_) {}),
          ])),
        )));
        expect(find.text('Total due'), findsOneWidget);
        expect(find.text('Complete & Print'), findsOneWidget);
        expect(find.text('Complete Sale'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('actions preserve chosen receipt behavior and block while submitting', (tester) async {
    final choices = <bool>[];
    Future<void> show(bool busy) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter,
        child: CheckoutActions(totalLabel: '\$5.00', enabled: true,
          isSubmitting: busy, onComplete: choices.add))),
    ));
    await show(false);
    await tester.tap(find.text('Complete & Print'));
    await tester.tap(find.text('Complete Sale'));
    expect(choices, [true, false]);
    await show(true);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });
}
