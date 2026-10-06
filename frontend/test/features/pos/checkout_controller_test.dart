import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/pos/application/checkout_controller.dart';
import 'package:top_coffee_pos/features/pos/application/checkout_state.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

class MockPosRepository extends Mock implements PosRepository {}

const _americano = PosProduct(
  id: 1,
  name: 'Americano',
  sku: null,
  description: null,
  category: null,
  price: 2.50,
  variants: [],
);

const _confirmation = OrderConfirmation(
  orderId: 42,
  total: 2.50,
  paymentMethod: 'cash',
  tendered: 5.00,
  changeDue: 2.50,
);

void main() {
  late MockPosRepository repository;

  setUp(() {
    repository = MockPosRepository();
  });

  ({ProviderContainer container, CheckoutController controller}) build() {
    final container = ProviderContainer(
      overrides: [posRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(checkoutControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  test('starts in CheckoutIdle', () {
    final built = build();
    expect(built.container.read(checkoutControllerProvider), isA<CheckoutIdle>());
  });

  test('submit() transitions to CheckoutSuccess on success', () async {
    when(() => repository.createOrder(
          items: any(named: 'items'),
          paymentMethod: any(named: 'paymentMethod'),
          orderType: any(named: 'orderType'),
          tendered: any(named: 'tendered'),
          discountTotal: any(named: 'discountTotal'),
        )).thenAnswer((_) async => _confirmation);

    final built = build();
    await built.controller.submit(
      items: const [CartItem(product: _americano, quantity: 1)],
      paymentMethod: 'cash',
      orderType: 'takeaway',
      tendered: 5.00,
      discountTotal: 0,
    );

    final state = built.container.read(checkoutControllerProvider);
    expect(state, isA<CheckoutSuccess>());
    expect((state as CheckoutSuccess).confirmation.orderId, 42);
  });

  test('hold() forwards the selected customer ID', () async {
    when(() => repository.holdOrder(
          items: any(named: 'items'),
          orderType: any(named: 'orderType'),
          tableId: any(named: 'tableId'),
          discountTotal: any(named: 'discountTotal'),
          customerId: any(named: 'customerId'),
        )).thenAnswer((_) async => _confirmation);

    final built = build();

    await built.controller.hold(
      items: const [CartItem(product: _americano, quantity: 1)],
      orderType: 'dine_in',
      tableId: 1,
      discountTotal: 0,
      customerId: 7,
    );

    expect(
      built.container.read(checkoutControllerProvider),
      isA<CheckoutHeld>(),
    );

    verify(() => repository.holdOrder(
          items: any(named: 'items'),
          orderType: 'dine_in',
          tableId: 1,
          discountTotal: 0,
          customerId: 7,
        )).called(1);
  });
  test('submit() transitions to CheckoutError with the backend message on failure', () async {
    when(() => repository.createOrder(
          items: any(named: 'items'),
          paymentMethod: any(named: 'paymentMethod'),
          orderType: any(named: 'orderType'),
          tendered: any(named: 'tendered'),
          discountTotal: any(named: 'discountTotal'),
        )).thenThrow(const ValidationException({}, 'Product is not available at this branch.'));

    final built = build();
    await built.controller.submit(
      items: const [CartItem(product: _americano, quantity: 1)],
      paymentMethod: 'card',
      orderType: 'takeaway',
      discountTotal: 0,
    );

    final state = built.container.read(checkoutControllerProvider);
    expect(state, isA<CheckoutError>());
    expect((state as CheckoutError).message, 'Product is not available at this branch.');
  });

  test('a failed checkout does not throw when the container is disposed mid-submit', () async {
    when(() => repository.createOrder(
          items: any(named: 'items'),
          paymentMethod: any(named: 'paymentMethod'),
          orderType: any(named: 'orderType'),
          tendered: any(named: 'tendered'),
          discountTotal: any(named: 'discountTotal'),
        )).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _confirmation;
    });

    final container = ProviderContainer(
      overrides: [posRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(checkoutControllerProvider.notifier);

    final submitFuture = controller.submit(
      items: const [CartItem(product: _americano, quantity: 1)],
      paymentMethod: 'cash',
      orderType: 'takeaway',
      tendered: 5.00,
      discountTotal: 0,
    );

    container.dispose();

    await expectLater(submitFuture, completes);
  });
}


