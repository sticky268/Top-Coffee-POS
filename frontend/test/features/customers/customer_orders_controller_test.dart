import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/customers/application/customer_orders_controller.dart';
import 'package:top_coffee_pos/features/customers/application/customer_orders_state.dart';
import 'package:top_coffee_pos/features/customers/data/customers_repository.dart';
import 'package:top_coffee_pos/features/customers/domain/customer_models.dart';

class MockCustomersRepository extends Mock implements CustomersRepository {}

CustomerOrder _order({
  int id = 12,
  int customerId = 5,
}) =>
    CustomerOrder(
      id: id,
      uuid: 'order-uuid-$id',
      branchId: 1,
      userId: 2,
      customerId: customerId,
      tableId: null,
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 25,
      discountTotal: 0,
      taxTotal: 0.5,
      total: 25.5,
      heldAt: null,
      completedAt: DateTime.parse('2026-09-30T10:00:00Z'),
      createdAt: DateTime.parse('2026-09-30T09:50:00Z'),
    );

CustomerOrderPage _page({
  List<CustomerOrder>? data,
  int currentPage = 1,
  int lastPage = 1,
  int total = 1,
}) =>
    CustomerOrderPage(
      data: data ?? [_order()],
      currentPage: currentPage,
      lastPage: lastPage,
      perPage: 20,
      total: total,
    );

void main() {
  late MockCustomersRepository repository;

  setUp(() {
    repository = MockCustomersRepository();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        customersRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);
    return container;
  }

  test('loads customer orders successfully', () async {
    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();

    final controller =
        container.read(customerOrdersControllerProvider(5).notifier);

    await controller.initialization;

    final state = container.read(customerOrdersControllerProvider(5));

    expect(state, isA<CustomerOrdersLoaded>());

    final loaded = state as CustomerOrdersLoaded;
    expect(loaded.orders, hasLength(1));
    expect(loaded.orders.single.id, 12);
    expect(loaded.orders.single.customerId, 5);
  });

  test('repository failure results in CustomerOrdersError', () async {
    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).thenThrow(Exception('network down'));

    final container = buildContainer();

    final controller =
        container.read(customerOrdersControllerProvider(5).notifier);

    await controller.initialization;

    final state = container.read(customerOrdersControllerProvider(5));

    expect(state, isA<CustomerOrdersError>());
    expect(
      (state as CustomerOrdersError).message,
      'Something went wrong',
    );
  });

  test('refresh reloads customer orders', () async {
    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();

    final controller =
        container.read(customerOrdersControllerProvider(5).notifier);

    await controller.initialization;
    await controller.refresh();

    verify(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).called(2);
  });

  test('loadMore appends the next page', () async {
    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).thenAnswer(
      (_) async => _page(
        data: [_order(id: 12)],
        currentPage: 1,
        lastPage: 2,
        total: 2,
      ),
    );

    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 2,
        perPage: 20,
      ),
    ).thenAnswer(
      (_) async => _page(
        data: [_order(id: 13)],
        currentPage: 2,
        lastPage: 2,
        total: 2,
      ),
    );

    final container = buildContainer();

    final controller =
        container.read(customerOrdersControllerProvider(5).notifier);

    await controller.initialization;
    await controller.loadMore();

    final state = container.read(customerOrdersControllerProvider(5));

    expect(state, isA<CustomerOrdersLoaded>());

    final loaded = state as CustomerOrdersLoaded;
    expect(
      loaded.orders.map((order) => order.id),
      [12, 13],
    );
    expect(loaded.currentPage, 2);
    expect(loaded.hasMore, isFalse);
    expect(loaded.isLoadingMore, isFalse);
  });

  test('loadMore failure keeps the existing orders', () async {
    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 1,
        perPage: 20,
      ),
    ).thenAnswer(
      (_) async => _page(
        currentPage: 1,
        lastPage: 2,
        total: 2,
      ),
    );

    when(
      () => repository.getCustomerOrders(
        customerId: 5,
        page: 2,
        perPage: 20,
      ),
    ).thenThrow(Exception('network down'));

    final container = buildContainer();

    final controller =
        container.read(customerOrdersControllerProvider(5).notifier);

    await controller.initialization;
    await controller.loadMore();

    final state = container.read(customerOrdersControllerProvider(5));

    expect(state, isA<CustomerOrdersLoaded>());

    final loaded = state as CustomerOrdersLoaded;
    expect(loaded.orders, hasLength(1));
    expect(loaded.orders.single.id, 12);
    expect(loaded.isLoadingMore, isFalse);
  });
}
