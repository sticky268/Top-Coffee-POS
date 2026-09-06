import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/application/order_detail_controller.dart';
import 'package:top_coffee_pos/features/orders/application/order_detail_state.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';

class MockOrdersRepository extends Mock implements OrdersRepository {}

const _detail = OrderDetail(
  id: 42,
  uuid: 'abc-123',
  orderType: 'takeaway',
  status: 'completed',
  subtotal: 10.0,
  discountTotal: 0,
  total: 10.0,
  branch: null,
  cashier: null,
  items: [],
  payment: null,
  createdAt: null,
);

void main() {
  late MockOrdersRepository repository;

  setUp(() {
    repository = MockOrdersRepository();
  });

  ({ProviderContainer container, OrderDetailController controller}) buildAndStart(int orderId) {
    final container = ProviderContainer(
      overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(orderDetailControllerProvider(orderId).notifier);
    return (container: container, controller: controller);
  }

  test('loads the requested order id into OrderDetailLoaded', () async {
    when(() => repository.getOrder(42)).thenAnswer((_) async => _detail);

    final built = buildAndStart(42);
    await built.controller.initialization;

    final state = built.container.read(orderDetailControllerProvider(42));
    expect(state, isA<OrderDetailLoaded>());
    expect((state as OrderDetailLoaded).order.id, 42);
    verify(() => repository.getOrder(42)).called(1);
  });

  test('a repository failure (e.g. another branch / not found) results in OrderDetailError', () async {
    when(() => repository.getOrder(999)).thenThrow(Exception('not found'));

    final built = buildAndStart(999);
    await built.controller.initialization;

    expect(built.container.read(orderDetailControllerProvider(999)), isA<OrderDetailError>());
  });

  test('refresh() can recover from a prior error', () async {
    when(() => repository.getOrder(42)).thenThrow(Exception('down'));
    final built = buildAndStart(42);
    await built.controller.initialization;
    expect(built.container.read(orderDetailControllerProvider(42)), isA<OrderDetailError>());

    when(() => repository.getOrder(42)).thenAnswer((_) async => _detail);
    await built.controller.refresh();

    expect(built.container.read(orderDetailControllerProvider(42)), isA<OrderDetailLoaded>());
  });

  test('does not throw when the container is disposed mid-load', () async {
    when(() => repository.getOrder(42)).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _detail;
    });

    final container = ProviderContainer(
      overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(orderDetailControllerProvider(42).notifier);

    container.dispose();

    await expectLater(controller.initialization, completes);
  });
}
