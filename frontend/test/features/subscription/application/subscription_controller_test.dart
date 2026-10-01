import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/subscription/application/subscription_controller.dart';
import 'package:top_coffee_pos/features/subscription/application/subscription_state.dart';
import 'package:top_coffee_pos/features/subscription/data/subscription_repository.dart';
import 'package:top_coffee_pos/features/subscription/domain/subscription_models.dart';

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

SubscriptionDetails _subscription({
  String status = 'trial',
  bool isActive = true,
  bool isExpired = false,
  bool canModify = true,
  String? expiresAt,
}) {
  return SubscriptionDetails(
    plan: const SubscriptionPlan(
      id: 1,
      name: '1 Branch',
      slug: '1-branch',
      branchLimit: 1,
      price: 0,
      billingInterval: 'monthly',
      isActive: true,
    ),
    branchUsage: const BranchUsage(
      current: 1,
      limit: 1,
      remaining: 0,
    ),
    subscription: SubscriptionStatus(
      status: status,
      startedAt: DateTime.parse('2026-09-29T10:00:00+00:00'),
      expiresAt: expiresAt == null ? null : DateTime.parse(expiresAt),
      isActive: isActive,
      isExpired: isExpired,
      canModify: canModify,
    ),
  );
}

void main() {
  late MockSubscriptionRepository repository;

  setUp(() {
    repository = MockSubscriptionRepository();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    return container;
  }

  test('starts in loading and then loads an active trial subscription',
      () async {
    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(),
    );

    final container = buildContainer();

    expect(
      container.read(subscriptionControllerProvider),
      isA<SubscriptionLoading>(),
    );

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionLoaded>());

    final loaded = state as SubscriptionLoaded;

    expect(loaded.subscription.plan!.name, '1 Branch');
    expect(loaded.subscription.subscription.status, 'trial');
    expect(loaded.canModify, isTrue);
    expect(loaded.isReadOnly, isFalse);
  });

  test('loads an expired subscription as read-only', () async {
    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(
        status: 'expired',
        isActive: false,
        isExpired: true,
        canModify: false,
        expiresAt: '2026-09-01T10:00:00+00:00',
      ),
    );

    final container = buildContainer();

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionLoaded>());

    final loaded = state as SubscriptionLoaded;

    expect(loaded.isExpired, isTrue);
    expect(loaded.canModify, isFalse);
    expect(loaded.isReadOnly, isTrue);
  });

  test('loads a suspended subscription as read-only', () async {
    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(
        status: 'suspended',
        isActive: false,
        isExpired: false,
        canModify: false,
      ),
    );

    final container = buildContainer();

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionLoaded>());

    final loaded = state as SubscriptionLoaded;

    expect(loaded.isSuspended, isTrue);
    expect(loaded.isExpired, isFalse);
    expect(loaded.canModify, isFalse);
    expect(loaded.isReadOnly, isTrue);
  });

  test('repository failure results in SubscriptionError', () async {
    when(() => repository.getSubscription()).thenThrow(
      Exception('network down'),
    );

    final container = buildContainer();

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    final state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionError>());
    expect(state, isNot(isA<SubscriptionLoading>()));

    final error = state as SubscriptionError;

    expect(error.message, 'Something went wrong');
  });

  test('refresh reloads subscription and replaces the current state', () async {
    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(),
    );

    final container = buildContainer();

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    var state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionLoaded>());

    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(
        status: 'active',
        isActive: true,
        isExpired: false,
        canModify: true,
        expiresAt: '2026-10-01T10:00:00+00:00',
      ),
    );

    await controller.refresh();

    state = container.read(subscriptionControllerProvider);

    expect(state, isA<SubscriptionLoaded>());

    final loaded = state as SubscriptionLoaded;

    expect(loaded.subscription.subscription.status, 'active');
    expect(loaded.subscription.subscription.expiresAt, isNotNull);
    expect(loaded.canModify, isTrue);

    verify(() => repository.getSubscription()).called(2);
  });

  test(
      'initialization completes even when repository returns a suspended state',
      () async {
    when(() => repository.getSubscription()).thenAnswer(
      (_) async => _subscription(
        status: 'suspended',
        isActive: false,
        canModify: false,
      ),
    );

    final container = buildContainer();

    final controller = container.read(subscriptionControllerProvider.notifier);

    await controller.initialization;

    expect(
      container.read(subscriptionControllerProvider),
      isA<SubscriptionLoaded>(),
    );

    verify(() => repository.getSubscription()).called(1);
  });
}
