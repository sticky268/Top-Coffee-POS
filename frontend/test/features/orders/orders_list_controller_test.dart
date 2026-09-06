import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/application/orders_list_controller.dart';
import 'package:top_coffee_pos/features/orders/application/orders_list_state.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';

class MockOrdersRepository extends Mock implements OrdersRepository {}

OrderSummary _order(int id) => OrderSummary(
      id: id,
      uuid: 'uuid-$id',
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 5.0,
      discountTotal: 0,
      total: 5.0,
      branch: null,
      cashier: null,
      payment: null,
      createdAt: null,
    );

void main() {
  late MockOrdersRepository repository;

  setUp(() {
    repository = MockOrdersRepository();
  });

  /// Same pattern established for every other controller: reading
  /// `.notifier` forces the lazy provider to construct immediately, and
  /// `initialization` is a deterministic completion signal.
  ({ProviderContainer container, OrdersListController controller}) buildAndStart() {
    final container = ProviderContainer(
      overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(ordersListControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  test('loads page 1 into OrdersListLoaded', () async {
    when(() => repository.getOrders(page: 1)).thenAnswer(
      (_) async => OrderListPage(orders: [_order(1), _order(2)], currentPage: 1, lastPage: 2, total: 3),
    );

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(ordersListControllerProvider);
    expect(state, isA<OrdersListLoaded>());
    final loaded = state as OrdersListLoaded;
    expect(loaded.orders, hasLength(2));
    expect(loaded.hasMore, isTrue);
  });

  test('a repository failure results in OrdersListError, never a stuck Loading', () async {
    when(() => repository.getOrders(page: 1)).thenThrow(Exception('network down'));

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(ordersListControllerProvider);
    expect(state, isNot(isA<OrdersListLoading>()));
    expect(state, isA<OrdersListError>());
  });

  test('refresh() reloads page 1 from scratch and can recover from an error', () async {
    when(() => repository.getOrders(page: 1)).thenThrow(Exception('down'));
    final built = buildAndStart();
    await built.controller.initialization;
    expect(built.container.read(ordersListControllerProvider), isA<OrdersListError>());

    when(() => repository.getOrders(page: 1)).thenAnswer(
      (_) async => OrderListPage(orders: [_order(1)], currentPage: 1, lastPage: 1, total: 1),
    );
    await built.controller.refresh();

    expect(built.container.read(ordersListControllerProvider), isA<OrdersListLoaded>());
  });

  group('loadMore', () {
    test('appends the next page and advances currentPage', () async {
      when(() => repository.getOrders(page: 1)).thenAnswer(
        (_) async => OrderListPage(orders: [_order(1)], currentPage: 1, lastPage: 2, total: 2),
      );
      when(() => repository.getOrders(page: 2)).thenAnswer(
        (_) async => OrderListPage(orders: [_order(2)], currentPage: 2, lastPage: 2, total: 2),
      );

      final built = buildAndStart();
      await built.controller.initialization;

      await built.controller.loadMore();

      final loaded = built.container.read(ordersListControllerProvider) as OrdersListLoaded;
      expect(loaded.orders, hasLength(2));
      expect(loaded.orders.map((o) => o.id), [1, 2]);
      expect(loaded.currentPage, 2);
      expect(loaded.hasMore, isFalse);
    });

    test('is a no-op when there is no next page', () async {
      when(() => repository.getOrders(page: 1)).thenAnswer(
        (_) async => OrderListPage(orders: [_order(1)], currentPage: 1, lastPage: 1, total: 1),
      );

      final built = buildAndStart();
      await built.controller.initialization;

      await built.controller.loadMore();

      verifyNever(() => repository.getOrders(page: 2));
    });

    test('a failed loadMore keeps the already-loaded orders and clears isLoadingMore', () async {
      when(() => repository.getOrders(page: 1)).thenAnswer(
        (_) async => OrderListPage(orders: [_order(1)], currentPage: 1, lastPage: 2, total: 2),
      );
      when(() => repository.getOrders(page: 2)).thenThrow(Exception('down'));

      final built = buildAndStart();
      await built.controller.initialization;

      await built.controller.loadMore();

      final loaded = built.container.read(ordersListControllerProvider) as OrdersListLoaded;
      expect(loaded.orders, hasLength(1)); // unchanged
      expect(loaded.isLoadingMore, isFalse);
    });
  });

  test('does not throw when the container is disposed mid-load', () async {
    when(() => repository.getOrders(page: 1)).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return OrderListPage(orders: [_order(1)], currentPage: 1, lastPage: 1, total: 1);
    });

    final container = ProviderContainer(
      overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(ordersListControllerProvider.notifier);

    container.dispose();

    await expectLater(controller.initialization, completes);
  });
}
