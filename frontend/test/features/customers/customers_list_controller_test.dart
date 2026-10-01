import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/customers/application/customers_list_controller.dart';
import 'package:top_coffee_pos/features/customers/application/customers_list_state.dart';
import 'package:top_coffee_pos/features/customers/data/customers_repository.dart';
import 'package:top_coffee_pos/features/customers/domain/customer_models.dart';

class MockCustomersRepository extends Mock implements CustomersRepository {}

Customer _customer({
  int id = 5,
  String name = 'John Doe',
}) =>
    Customer(
      id: id,
      branchId: 1,
      name: name,
      phone: '012345678',
      email: null,
      notes: null,
      completedOrdersCount: 2,
      completedOrdersTotal: 20,
    );

CustomerListPage _page({
  List<Customer>? data,
  int currentPage = 1,
  int lastPage = 1,
  int total = 1,
}) =>
    CustomerListPage(
      data: data ?? [_customer()],
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

  test('loads customers into CustomersListLoaded', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();

    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(customersListControllerProvider);

    expect(state, isA<CustomersListLoaded>());

    final loaded = state as CustomersListLoaded;
    expect(loaded.customers, hasLength(1));
    expect(loaded.customers.single.id, 5);
    expect(loaded.currentPage, 1);
    expect(loaded.hasMore, isFalse);
  });

  test('repository failure results in CustomersListError', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenThrow(Exception('network down'));

    final container = buildContainer();

    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(customersListControllerProvider);

    expect(state, isA<CustomersListError>());
    expect(
      (state as CustomersListError).message,
      'Something went wrong',
    );
  });

  test('applySearch refreshes using the trimmed search value', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();
    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;

    when(
      () => repository.getCustomers(
        search: 'John',
        branchId: null,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _page(
        data: [_customer(name: 'John Smith')],
      ),
    );

    await controller.applySearch('  John  ');

    final state = container.read(customersListControllerProvider);
    expect(state, isA<CustomersListLoaded>());
    expect(
      (state as CustomersListLoaded).customers.single.name,
      'John Smith',
    );

    verify(
      () => repository.getCustomers(
        search: 'John',
        branchId: null,
        page: 1,
      ),
    ).called(1);
  });

  test('clearSearch refreshes without a search term', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();
    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;

    when(
      () => repository.getCustomers(
        search: 'John',
        branchId: null,
        page: 1,
      ),
    ).thenAnswer((_) async => _page());

    await controller.applySearch('John');

    await controller.clearSearch();

    verify(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).called(2);
  });

  test('loadMore appends the next page', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _page(
        data: [_customer(id: 5)],
        currentPage: 1,
        lastPage: 2,
        total: 2,
      ),
    );

    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 2,
      ),
    ).thenAnswer(
      (_) async => _page(
        data: [_customer(id: 6, name: 'Jane Doe')],
        currentPage: 2,
        lastPage: 2,
        total: 2,
      ),
    );

    final container = buildContainer();
    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;
    await controller.loadMore();

    final state = container.read(customersListControllerProvider);

    expect(state, isA<CustomersListLoaded>());

    final loaded = state as CustomersListLoaded;
    expect(loaded.customers.map((customer) => customer.id), [5, 6]);
    expect(loaded.currentPage, 2);
    expect(loaded.hasMore, isFalse);
    expect(loaded.isLoadingMore, isFalse);
  });

  test('loadMore does nothing when there are no more pages', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer((_) async => _page());

    final container = buildContainer();
    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;
    await controller.loadMore();

    verify(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).called(1);
  });

  test('loadMore keeps the existing list when the next page fails', () async {
    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _page(
        currentPage: 1,
        lastPage: 2,
        total: 2,
      ),
    );

    when(
      () => repository.getCustomers(
        search: null,
        branchId: null,
        page: 2,
      ),
    ).thenThrow(Exception('network down'));

    final container = buildContainer();
    final controller =
        container.read(customersListControllerProvider.notifier);

    await controller.initialization;
    await controller.loadMore();

    final state = container.read(customersListControllerProvider);
    expect(state, isA<CustomersListLoaded>());

    final loaded = state as CustomersListLoaded;
    expect(loaded.customers, hasLength(1));
    expect(loaded.isLoadingMore, isFalse);
  });
}
