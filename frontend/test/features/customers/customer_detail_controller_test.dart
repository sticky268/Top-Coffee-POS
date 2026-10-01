import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/customers/application/customer_detail_controller.dart';
import 'package:top_coffee_pos/features/customers/application/customer_detail_state.dart';
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
      email: 'john@example.com',
      notes: 'VIP',
      completedOrdersCount: 3,
      completedOrdersTotal: 30,
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

  test('loads customer successfully', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    final state = container.read(customerDetailControllerProvider(5));

    expect(state, isA<CustomerDetailLoaded>());

    final loaded = state as CustomerDetailLoaded;
    expect(loaded.customer.id, 5);
    expect(loaded.customer.name, 'John Doe');
  });

  test('repository failure results in CustomerDetailError', () async {
    when(() => repository.getCustomer(5))
        .thenThrow(Exception('network down'));

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    final state = container.read(customerDetailControllerProvider(5));

    expect(state, isA<CustomerDetailError>());
    expect(
      (state as CustomerDetailError).message,
      'Something went wrong',
    );
  });

  test('refresh reloads the customer', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    await controller.refresh();

    verify(() => repository.getCustomer(5)).called(2);
  });

  test('updateCustomer returns the updated customer', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    when(
      () => repository.updateCustomer(
        id: 5,
        name: 'John Updated',
        phone: '098765432',
        email: 'updated@example.com',
        notes: 'Updated notes',
      ),
    ).thenAnswer(
      (_) async => _customer(name: 'John Updated'),
    );

    final updated = await controller.updateCustomer(
      name: 'John Updated',
      phone: '098765432',
      email: 'updated@example.com',
      notes: 'Updated notes',
    );

    expect(updated, isNotNull);
    expect(updated!.name, 'John Updated');

    final state = container.read(customerDetailControllerProvider(5));
    expect(state, isA<CustomerDetailLoaded>());
    expect(
      (state as CustomerDetailLoaded).customer.name,
      'John Updated',
    );
  });

  test('updateCustomer returns null when repository fails', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    when(
      () => repository.updateCustomer(
        id: 5,
        name: 'John Updated',
        phone: null,
        email: null,
        notes: null,
      ),
    ).thenThrow(Exception('update failed'));

    final updated = await controller.updateCustomer(
      name: 'John Updated',
      phone: null,
      email: null,
      notes: null,
    );

    expect(updated, isNull);

    final state = container.read(customerDetailControllerProvider(5));
    expect(state, isA<CustomerDetailError>());
    expect(
      (state as CustomerDetailError).message,
      'Something went wrong',
    );
  });

  test('deleteCustomer returns true when deletion succeeds', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    when(() => repository.deleteCustomer(5))
        .thenAnswer((_) async {});

    final deleted = await controller.deleteCustomer();

    expect(deleted, isTrue);
    verify(() => repository.deleteCustomer(5)).called(1);
  });

  test('deleteCustomer returns false when deletion fails', () async {
    when(() => repository.getCustomer(5))
        .thenAnswer((_) async => _customer());

    final container = buildContainer();

    final controller =
        container.read(customerDetailControllerProvider(5).notifier);

    await controller.initialization;

    when(() => repository.deleteCustomer(5))
        .thenThrow(Exception('delete failed'));

    final deleted = await controller.deleteCustomer();

    expect(deleted, isFalse);

    final state = container.read(customerDetailControllerProvider(5));
    expect(state, isA<CustomerDetailError>());
    expect(
      (state as CustomerDetailError).message,
      'Something went wrong',
    );
  });
}
