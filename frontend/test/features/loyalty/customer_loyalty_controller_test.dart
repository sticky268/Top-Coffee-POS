import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/customers/domain/customer_models.dart';
import 'package:top_coffee_pos/features/loyalty/application/customer_loyalty_controller.dart';
import 'package:top_coffee_pos/features/loyalty/application/customer_loyalty_state.dart';
import 'package:top_coffee_pos/features/loyalty/data/loyalty_repository.dart';
import 'package:top_coffee_pos/features/loyalty/domain/loyalty_models.dart';

class MockLoyaltyRepository extends Mock implements LoyaltyRepository {}

Customer _customer() => const Customer(
      id: 5,
      branchId: 1,
      name: 'John Doe',
      phone: '012345678',
      email: null,
      notes: null,
      completedOrdersCount: 3,
      completedOrdersTotal: 25.50,
    );

LoyaltyAccount _account({
  int pointsBalance = 250,
}) =>
    LoyaltyAccount(
      id: 10,
      customerId: 5,
      pointsBalance: pointsBalance,
      lifetimeEarned: 400,
      lifetimeRedeemed: 150,
    );

LoyaltyTransaction _transaction({
  int id = 20,
  String type = 'earned',
  int points = 100,
  int balanceAfter = 250,
}) =>
    LoyaltyTransaction(
      id: id,
      customerLoyaltyAccountId: 10,
      customerId: 5,
      branchId: 1,
      orderId: type == 'earned' ? 12 : null,
      type: type,
      points: points,
      balanceAfter: balanceAfter,
      description: type == 'adjustment'
          ? 'Welcome bonus'
          : 'Points earned from completed order',
    );

CustomerLoyalty _loyalty({
  int pointsBalance = 250,
}) =>
    CustomerLoyalty(
      customer: _customer(),
      account: _account(pointsBalance: pointsBalance),
      transactions: [_transaction(balanceAfter: pointsBalance)],
      currentPage: 1,
      lastPage: 1,
      perPage: 20,
      total: 1,
    );

void main() {
  late MockLoyaltyRepository repository;

  setUp(() {
    repository = MockLoyaltyRepository();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        loyaltyRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);
    return container;
  }

  test('loads customer loyalty into CustomerLoyaltyLoaded', () async {
    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _loyalty(),
    );

    final container = buildContainer();

    final controller =
        container.read(customerLoyaltyControllerProvider(5).notifier);

    await controller.initialization;

    final state =
        container.read(customerLoyaltyControllerProvider(5));

    expect(state, isA<CustomerLoyaltyLoaded>());

    final loaded = state as CustomerLoyaltyLoaded;

    expect(loaded.loyalty.customer.id, 5);
    expect(loaded.loyalty.account.pointsBalance, 250);
    expect(loaded.loyalty.transactions, hasLength(1));
  });

  test('repository failure results in CustomerLoyaltyError', () async {
    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenThrow(Exception('network down'));

    final container = buildContainer();

    final controller =
        container.read(customerLoyaltyControllerProvider(5).notifier);

    await controller.initialization;

    final state =
        container.read(customerLoyaltyControllerProvider(5));

    expect(state, isA<CustomerLoyaltyError>());
  });

  test('refresh reloads customer loyalty from page 1', () async {
    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _loyalty(pointsBalance: 250),
    );

    final container = buildContainer();

    final controller =
        container.read(customerLoyaltyControllerProvider(5).notifier);

    await controller.initialization;

    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _loyalty(pointsBalance: 300),
    );

    await controller.refresh();

    final state =
        container.read(customerLoyaltyControllerProvider(5));

    expect(state, isA<CustomerLoyaltyLoaded>());

    final loaded = state as CustomerLoyaltyLoaded;

    expect(loaded.loyalty.account.pointsBalance, 300);

    verify(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).called(2);
  });

  test('adjustPoints adjusts points and reloads the loyalty data', () async {
    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _loyalty(pointsBalance: 250),
    );

    when(
      () => repository.adjustCustomerLoyalty(
        customerId: 5,
        points: 50,
        description: 'Welcome bonus',
        branchId: 1,
      ),
    ).thenAnswer(
      (_) async => _transaction(
        id: 21,
        type: 'adjustment',
        points: 50,
        balanceAfter: 300,
      ),
    );

    final container = buildContainer();

    final controller =
        container.read(customerLoyaltyControllerProvider(5).notifier);

    await controller.initialization;

    when(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).thenAnswer(
      (_) async => _loyalty(pointsBalance: 300),
    );

    final result = await controller.adjustPoints(
      points: 50,
      description: 'Welcome bonus',
      branchId: 1,
    );

    expect(result, isTrue);

    final state =
        container.read(customerLoyaltyControllerProvider(5));

    expect(state, isA<CustomerLoyaltyLoaded>());

    final loaded = state as CustomerLoyaltyLoaded;

    expect(loaded.loyalty.account.pointsBalance, 300);

    verify(
      () => repository.adjustCustomerLoyalty(
        customerId: 5,
        points: 50,
        description: 'Welcome bonus',
        branchId: 1,
      ),
    ).called(1);

    verify(
      () => repository.getCustomerLoyalty(
        customerId: 5,
        page: 1,
      ),
    ).called(2);
  });
}