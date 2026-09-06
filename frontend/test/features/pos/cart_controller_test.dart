import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

const _latte = PosProduct(
  id: 1,
  name: 'Latte',
  sku: null,
  description: null,
  category: null,
  price: 3.00,
  variants: [
    PosProductVariant(id: 10, name: 'Medium', price: 3.00),
    PosProductVariant(id: 11, name: 'Large', price: 3.50),
  ],
);

const _americano = PosProduct(
  id: 2,
  name: 'Americano',
  sku: null,
  description: null,
  category: null,
  price: 2.50,
  variants: [],
);

void main() {
  late ProviderContainer container;
  late CartController controller;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    controller = container.read(cartControllerProvider.notifier);
  });

  test('starts empty', () {
    final state = container.read(cartControllerProvider);
    expect(state.isEmpty, isTrue);
    expect(state.subtotal, 0);
    expect(state.total, 0);
  });

  test('adding a product with no variant creates one line', () {
    controller.addItem(_americano);

    final state = container.read(cartControllerProvider);
    expect(state.items, hasLength(1));
    expect(state.items.single.quantity, 1);
    expect(state.subtotal, 2.50);
  });

  test('adding the same product+variant twice increases quantity instead of duplicating the line', () {
    controller.addItem(_latte, variant: _latte.variants[0]); // Medium
    controller.addItem(_latte, variant: _latte.variants[0]); // Medium again

    final state = container.read(cartControllerProvider);
    expect(state.items, hasLength(1));
    expect(state.items.single.quantity, 2);
    expect(state.subtotal, 6.00); // 2 x 3.00
  });

  test('different variants of the same product never merge into one line', () {
    controller.addItem(_latte, variant: _latte.variants[0]); // Medium — $3.00
    controller.addItem(_latte, variant: _latte.variants[1]); // Large — $3.50

    final state = container.read(cartControllerProvider);
    expect(state.items, hasLength(2));

    final medium = state.items.firstWhere((i) => i.variant?.name == 'Medium');
    final large = state.items.firstWhere((i) => i.variant?.name == 'Large');
    expect(medium.quantity, 1);
    expect(large.quantity, 1);
    expect(state.subtotal, 6.50); // 3.00 + 3.50
  });

  test('incrementQuantity increases the correct line only', () {
    controller.addItem(_americano);
    controller.addItem(_latte, variant: _latte.variants[0]);

    final americanoKey = container.read(cartControllerProvider).items.firstWhere((i) => i.product.id == 2).lineKey;
    controller.incrementQuantity(americanoKey);

    final state = container.read(cartControllerProvider);
    final americanoLine = state.items.firstWhere((i) => i.product.id == 2);
    final latteLine = state.items.firstWhere((i) => i.product.id == 1);
    expect(americanoLine.quantity, 2);
    expect(latteLine.quantity, 1); // untouched
  });

  test('decrementQuantity to zero removes the line', () {
    controller.addItem(_americano);
    final key = container.read(cartControllerProvider).items.single.lineKey;

    controller.decrementQuantity(key);

    expect(container.read(cartControllerProvider).items, isEmpty);
  });

  test('decrementQuantity above zero just reduces quantity', () {
    controller.addItem(_americano);
    controller.addItem(_americano); // quantity 2
    final key = container.read(cartControllerProvider).items.single.lineKey;

    controller.decrementQuantity(key);

    final state = container.read(cartControllerProvider);
    expect(state.items, hasLength(1));
    expect(state.items.single.quantity, 1);
  });

  test('removeItem removes the line regardless of quantity', () {
    controller.addItem(_americano);
    controller.addItem(_americano);
    controller.addItem(_americano); // quantity 3
    final key = container.read(cartControllerProvider).items.single.lineKey;

    controller.removeItem(key);

    expect(container.read(cartControllerProvider).items, isEmpty);
  });

  test('clear empties the whole cart', () {
    controller.addItem(_americano);
    controller.addItem(_latte, variant: _latte.variants[0]);

    controller.clear();

    expect(container.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('subtotal and total reflect multiple distinct lines correctly', () {
    controller.addItem(_americano); // $2.50 x1
    controller.addItem(_americano); // -> x2 = $5.00
    controller.addItem(_latte, variant: _latte.variants[1]); // Large $3.50 x1

    final state = container.read(cartControllerProvider);
    expect(state.totalItemCount, 3);
    expect(state.subtotal, 8.50);
    expect(state.total, state.subtotal); // no tax/discount modeling yet
  });

  test('adjusting or removing a non-existent lineKey is a safe no-op', () {
    controller.addItem(_americano);

    controller.incrementQuantity('does-not-exist');
    controller.decrementQuantity('does-not-exist');
    controller.removeItem('does-not-exist');

    expect(container.read(cartControllerProvider).items, hasLength(1));
  });

  group('discount', () {
    test('setDiscount reduces total but not subtotal', () {
      controller.addItem(_americano); // $2.50
      controller.setDiscount(1.00);

      final state = container.read(cartControllerProvider);
      expect(state.subtotal, 2.50);
      expect(state.discountTotal, 1.00);
      expect(state.total, 1.50);
    });

    test('total never goes negative even if discount exceeds subtotal', () {
      controller.addItem(_americano); // $2.50
      controller.setDiscount(100.00);

      expect(container.read(cartControllerProvider).total, 0);
    });

    test('a negative discount amount is clamped to zero', () {
      controller.addItem(_americano);
      controller.setDiscount(-5.00);

      expect(container.read(cartControllerProvider).discountTotal, 0);
    });

    test('discount survives adding/removing items', () {
      controller.addItem(_americano);
      controller.setDiscount(0.50);

      controller.addItem(_latte, variant: _latte.variants[0]);

      expect(container.read(cartControllerProvider).discountTotal, 0.50);
    });

    test('clear() resets the discount along with the items', () {
      controller.addItem(_americano);
      controller.setDiscount(0.50);

      controller.clear();

      final state = container.read(cartControllerProvider);
      expect(state.items, isEmpty);
      expect(state.discountTotal, 0);
    });
  });
}
