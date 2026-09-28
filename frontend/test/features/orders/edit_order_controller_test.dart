import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/application/edit_order_controller.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_state.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

class MockOrdersRepository extends Mock implements OrdersRepository {}

const _category = PosProductCategoryRef(
  id: 1,
  name: 'Coffee',
);

const _latte = PosProduct(
  id: 5,
  name: 'Latte',
  sku: 'LATTE',
  description: null,
  category: _category,
  price: 3.0,
  variants: [
    PosProductVariant(
      id: 2,
      name: 'Large',
      price: 4.0,
    ),
  ],
);

const _americano = PosProduct(
  id: 6,
  name: 'Americano',
  sku: 'AMER',
  description: null,
  category: _category,
  price: 2.5,
  variants: [],
);

const _catalog = PosCatalogLoaded(
  categories: [
    PosCategory(
      id: 1,
      name: 'Coffee',
      sortOrder: 1,
    ),
  ],
  products: [
    _latte,
    _americano,
  ],
);

const _order = OrderDetail(
  id: 42,
  uuid: 'abc-123',
  orderType: 'takeaway',
  status: 'completed',
  subtotal: 8.0,
  discountTotal: 1.0,
  total: 7.0,
  branch: null,
  cashier: null,
  items: [
    OrderLineItem(
      id: 100,
      productId: 5,
      productVariantId: 2,
      productName: 'Latte',
      variantName: 'Large',
      quantity: 2,
      unitPrice: 4.0,
      lineTotal: 8.0,
    ),
  ],
  payment: null,
  createdAt: null,
);

void main() {
  late MockOrdersRepository repository;
  late EditOrderController controller;

  setUp(() {
    repository = MockOrdersRepository();

    controller = EditOrderController(
      repository,
      _catalog,
      _order,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('loads completed order items into isolated edit state', () {
    expect(controller.state.items, hasLength(1));
    expect(controller.state.items.first.product.id, 5);
    expect(controller.state.items.first.variant?.id, 2);
    expect(controller.state.items.first.quantity, 2);
    expect(controller.state.discountTotal, 1.0);
    expect(controller.state.subtotal, 8.0);
    expect(controller.state.total, 7.0);
  });

  test('adding the same product and variant increases quantity', () {
    controller.addItem(
      _latte,
      variant: _latte.variants.first,
    );

    expect(controller.state.items, hasLength(1));
    expect(controller.state.items.first.quantity, 3);
  });

  test('adding a different variant creates a separate line', () {
    controller.addItem(_latte);

    expect(controller.state.items, hasLength(2));
    expect(controller.state.items[0].lineKey, '5:2');
    expect(controller.state.items[1].lineKey, '5:base');
  });

  test('decrementing to zero removes the line', () {
    controller.decrementQuantity('5:2');
    controller.decrementQuantity('5:2');

    expect(controller.state.items, isEmpty);
  });

  test('discount cannot become negative', () {
    controller.setDiscount(-5);

    expect(controller.state.discountTotal, 0.0);
  });

  test('save sends product ids, variant ids and quantities without prices', () async {
    const updatedOrder = OrderDetail(
      id: 42,
      uuid: 'abc-123',
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 8.0,
      discountTotal: 1.0,
      total: 7.0,
      branch: null,
      cashier: null,
      items: [
        OrderLineItem(
          id: 101,
          productId: 5,
          productVariantId: 2,
          productName: 'Latte',
          variantName: 'Large',
          quantity: 2,
          unitPrice: 4.0,
          lineTotal: 8.0,
        ),
      ],
      payment: null,
      createdAt: null,
    );

    when(
      () => repository.updateOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 1.0,
        branchId: 2,
      ),
    ).thenAnswer((_) async => updatedOrder);

    final result = await controller.save(branchId: 2);

    expect(result?.id, 42);
    expect(controller.state.isSaving, isFalse);

    final captured = verify(
      () => repository.updateOrder(
        orderId: 42,
        items: captureAny(named: 'items'),
        discountTotal: 1.0,
        branchId: 2,
      ),
    ).captured.single as List<Map<String, dynamic>>;

    expect(
      captured,
      [
        {
          'product_id': 5,
          'product_variant_id': 2,
          'quantity': 2,
        },
      ],
    );

    expect(captured.first.containsKey('unit_price'), isFalse);
    expect(captured.first.containsKey('price'), isFalse);
  });

  test('save rejects an empty edit cart without calling the repository', () async {
    controller.removeItem('5:2');

    final result = await controller.save();

    expect(result, isNull);
    expect(controller.state.errorMessage, 'Order must contain at least one item.');
    verifyNever(
      () => repository.updateOrder(
        orderId: any(named: 'orderId'),
        items: any(named: 'items'),
        discountTotal: any(named: 'discountTotal'),
        branchId: any(named: 'branchId'),
      ),
    );
  });
}
