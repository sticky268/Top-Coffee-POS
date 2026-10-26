import 'package:flutter/material.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/cart_panel.dart';

void main() {
  testWidgets('short phone cart scrolls to checkout without overflowing', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 360, height: 220, child: CartPanel()),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    container.read(cartControllerProvider.notifier).addItem(
          const PosProduct(
            id: 1,
            name: 'Latte',
            sku: null,
            description: null,
            category: null,
            price: 3.5,
            variants: [],
          ),
        );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review Order'), 160,
        scrollable: find
            .descendant(
                of: find.byType(CartPanel), matching: find.byType(Scrollable))
            .first,
        maxScrolls: 30);
    await tester.pumpAndSettle();
    expect(find.text('Review Order').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final count in [1, 5, 10]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Studio cart $count lines fits and scrolls at text $scale',
          (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        for (var i = 0; i < count; i++) {
          container.read(cartControllerProvider.notifier).addItem(PosProduct(
              id: i + 1,
              name: 'កាហ្វេទឹកដោះគោ Long Khmer coffee name $i',
              sku: null,
              description: null,
              category: null,
              price: 3.5,
              variants: const []));
        }
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                theme: CoffeeStudioTheme.light,
                home: Scaffold(
                    body: MediaQuery(
                        data: MediaQueryData(
                            textScaler: TextScaler.linear(scale)),
                        child: const SizedBox(
                            width: 380, height: 300, child: CartPanel()))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Review Order'), 160,
            scrollable: find
                .descendant(
                    of: find.byType(CartPanel),
                    matching: find.byType(Scrollable))
                .first,
            maxScrolls: 30);
        await tester.pumpAndSettle();
        expect(find.text('Review Order').hitTestable(), findsOneWidget);
        expect(container.read(cartControllerProvider).totalItemCount, count);
        await tester.ensureVisible(find.text('Order details & discounts'));
        await tester.tap(find.text('Order details & discounts'));
        await tester.pumpAndSettle();
        expect(find.text('Subtotal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
