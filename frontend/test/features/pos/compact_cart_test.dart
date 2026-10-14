import 'package:flutter/material.dart';
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
    container
        .read(cartControllerProvider.notifier)
        .addItem(
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
    await tester.ensureVisible(find.text('Review Order'));
    await tester.pumpAndSettle();
    expect(find.text('Review Order').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
