import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/application/cart_state.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/menu_selection_sheet.dart';

const product = PosProduct(
  id: 1,
  name: 'Latte',
  sku: null,
  description: null,
  category: null,
  price: 3.75,
  variants: [],
  modifierGroups: [
    {
      'id': 1,
      'name': 'Milk',
      'is_required': true,
      'min_select': 1,
      'max_select': 1,
      'options': [
        {'id': 8, 'name': 'Oat', 'price_delta': '0.45'},
        {'id': 9, 'name': 'Soy', 'price_delta': '0.20'},
      ],
    },
  ],
);

void main() {
  test(
    'configured lines remain distinct and quantity changes preserve selections',
    () {
      final controller = CartController();
      controller.addItem(
        product,
        modifierIds: [8],
        extraCents: 45,
        configurationLabel: 'Oat',
      );
      controller.addItem(
        product,
        modifierIds: [9],
        extraCents: 20,
        configurationLabel: 'Soy',
      );
      controller.addItem(
        product,
        modifierIds: [8],
        extraCents: 45,
        configurationLabel: 'Oat',
      );
      expect(controller.state.items.length, 2);
      final oat = controller.state.items.first;
      expect(oat.quantity, 2);
      expect(oat.unitPrice, 4.2);
      controller.incrementQuantity(oat.lineKey);
      expect(controller.state.items.first.selectionPayload['modifier_ids'], [
        8,
      ]);
      expect(controller.state.items.first.configurationLabel, 'Oat');
      controller.dispose();
    },
  );

  test(
    'saved percentage discount tracks changed quantities with cent rounding',
    () {
      const cart = CartState(
        items: [CartItem(product: product, quantity: 1)],
        menuDiscount: {'id': 1, 'type': 'percent', 'value': '12.50'},
      );
      expect(cart.discountTotal, .47);
      final two = cart.copyWith(
        items: const [CartItem(product: product, quantity: 2)],
      );
      expect(two.discountTotal, .94);
      expect(
        two
            .copyWith(menuDiscount: const {'type': 'fixed', 'value': '50'})
            .total,
        0,
      );
      expect(
        two.copyWith(clearMenuDiscount: true, discountTotal: 1).discountTotal,
        1,
      );
    },
  );

  test(
    'catalog configuration survives JSON and combo selections identify cart lines',
    () {
      final combo = PosProduct.fromJson({
        'id': 2,
        'name': 'Pair',
        'price': 5.99,
        'variants': [],
        'combo_slots': [
          {
            'name': 'Drink',
            'quantity': 2,
            'choices': [
              {'product_id': 1, 'extra_price': '0.10'},
            ],
          },
        ],
        'modifier_groups': [],
      });
      expect(combo.needsConfiguration, true);
      expect(
        CartItem(
          product: combo,
          quantity: 1,
          comboSelections: const [1],
        ).lineKey,
        isNot(
          CartItem(
            product: combo,
            quantity: 1,
            comboSelections: const [2],
          ).lineKey,
        ),
      );
    },
  );

  testWidgets('modifier limit disables extra options until one is removed', (
    tester,
  ) async {
    final limited = PosProduct(
      id: 2,
      name: 'Toppings',
      sku: null,
      description: null,
      category: null,
      price: 3.75,
      variants: [],
      modifierGroups: [
        {
          ...product.modifierGroups.single,
          'max_select': 2,
          'options': [
            ...(product.modifierGroups.single['options'] as List),
            {'id': 10, 'name': 'Cream', 'price_delta': '0.30'},
          ],
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMenuSelection(context, limited),
              child: const Text('Configure'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oat (+\$0.45)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soy (+\$0.20)'));
    await tester.pumpAndSettle();
    final cream = find.widgetWithText(CheckboxListTile, 'Cream (+\$0.30)');
    expect(tester.widget<CheckboxListTile>(cream).onChanged, isNull);
    await tester.tap(find.text('Oat (+\$0.45)'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(cream).onChanged, isNotNull);
    await tester.tap(cream);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(cream).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required modifier prevents add until selected', (tester) async {
    CartItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showMenuSelection(context, product);
              },
              child: const Text('Configure'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add · \$3.75'));
    await tester.pumpAndSettle();
    expect(find.text('Check the number of choices.'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Oat (+\$0.45)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soy (+\$0.20)'));
    await tester.pumpAndSettle();
    expect(find.text('Check the number of choices.'), findsNothing);
    expect(find.text('Add · \$3.95'), findsOneWidget);
    await tester.tap(find.text('Oat (+\$0.45)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add · \$4.20'));
    await tester.pumpAndSettle();
    expect(result!.modifierIds, [8]);
    expect(result!.unitPrice, 4.2);
  });
}
