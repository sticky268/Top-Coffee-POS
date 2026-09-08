import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/orders/application/orders_list_controller.dart';
import 'package:top_coffee_pos/features/orders/application/orders_list_state.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';

class MockOrdersRepository extends Mock implements OrdersRepository {}

const branch74 = BranchSummary(
  id: 74,
  name: 'Top Coffee - Riverside',
  code: 'PP-01',
);

const branch75 = BranchSummary(
  id: 75,
  name: 'Top Coffee - BKK1',
  code: 'PP-02',
);

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

  ({ProviderContainer container, OrdersListController controller})
      buildAndStart({BranchSummary? branch}) {
    final container = ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
        currentBranchProvider.overrideWith((ref) {
          return CurrentBranchNotifier(ref, listenToAuth: false);
        }),
      ],
    );

    addTearDown(container.dispose);

    if (branch != null) {
      container
          .read(currentBranchProvider.notifier)
          .selectBranch(branch);
    }

    final controller =
        container.read(ordersListControllerProvider.notifier);

    return (container: container, controller: controller);
  }

  test('loads page 1 into OrdersListLoaded', () async {
    when(
      () => repository.getOrders(
        page: 1,
        branchId: 74,
      ),
    ).thenAnswer(
      (_) async => OrderListPage(
        orders: [_order(1), _order(2)],
        currentPage: 1,
        lastPage: 2,
        total: 3,
      ),
    );

    final built = buildAndStart(branch: branch74);

    await built.controller.initialization;

    final state = built.container.read(ordersListControllerProvider);

    expect(state, isA<OrdersListLoaded>());

    final loaded = state as OrdersListLoaded;

    expect(loaded.orders, hasLength(2));
    expect(loaded.hasMore, isTrue);
  });

  test(
    'a repository failure results in OrdersListError, never a stuck Loading',
    () async {
      when(
        () => repository.getOrders(
          page: 1,
          branchId: 74,
        ),
      ).thenThrow(Exception('network down'));

    final built = buildAndStart(branch: branch74);

      await built.controller.initialization;

      final state =
          built.container.read(ordersListControllerProvider);

      expect(state, isNot(isA<OrdersListLoading>()));
      expect(state, isA<OrdersListError>());
    },
  );

  test(
    'refresh() reloads page 1 from scratch and can recover from an error',
    () async {
      when(
        () => repository.getOrders(
          page: 1,
          branchId: 74,
        ),
      ).thenThrow(Exception('down'));

      final built = buildAndStart(branch: branch74);

      await built.controller.initialization;

      expect(
        built.container.read(ordersListControllerProvider),
        isA<OrdersListError>(),
      );

      when(
        () => repository.getOrders(
          page: 1,
          branchId: 74,
        ),
      ).thenAnswer(
        (_) async => OrderListPage(
          orders: [_order(1)],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );

      await built.controller.refresh();

      expect(
        built.container.read(ordersListControllerProvider),
        isA<OrdersListLoaded>(),
      );
    },
  );

  test('reloads orders when the current branch changes', () async {
    when(
      () => repository.getOrders(
        page: 1,
        branchId: 74,
      ),
    ).thenAnswer(
      (_) async => OrderListPage(
        orders: [_order(74)],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );

    when(
      () => repository.getOrders(
        page: 1,
        branchId: 75,
      ),
    ).thenAnswer(
      (_) async => OrderListPage(
        orders: [_order(75)],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );

    final built = buildAndStart(branch: branch74);
    await built.controller.initialization;

    var loaded =
        built.container.read(ordersListControllerProvider)
            as OrdersListLoaded;

    expect(loaded.orders.single.id, 74);

    built.container
        .read(currentBranchProvider.notifier)
        .selectBranch(branch75);

    await built.controller.initialization;

    loaded =
        built.container.read(ordersListControllerProvider)
            as OrdersListLoaded;

    expect(loaded.orders.single.id, 75);

    verify(
      () => repository.getOrders(
        page: 1,
        branchId: 74,
      ),
    ).called(1);

    verify(
      () => repository.getOrders(
        page: 1,
        branchId: 75,
      ),
    ).called(1);
  });

  group('loadMore', () {
    test(
      'appends the next page and advances currentPage',
      () async {
        when(
          () => repository.getOrders(
            page: 1,
            branchId: 74,
          ),
        ).thenAnswer(
          (_) async => OrderListPage(
            orders: [_order(1)],
            currentPage: 1,
            lastPage: 2,
            total: 2,
          ),
        );

        when(
          () => repository.getOrders(
            page: 2,
            branchId: 74,
          ),
        ).thenAnswer(
          (_) async => OrderListPage(
            orders: [_order(2)],
            currentPage: 2,
            lastPage: 2,
            total: 2,
          ),
        );

        final built = buildAndStart(branch: branch74);
        final controller = built.controller;
        final container = built.container;

        await controller.initialization;
        await controller.loadMore();

        final state = container.read(ordersListControllerProvider);

        expect(state, isA<OrdersListLoaded>());
        final loaded = state as OrdersListLoaded;

        expect(loaded.orders, hasLength(2));
        expect(loaded.orders.map((o) => o.id), [1, 2]);
        expect(loaded.currentPage, 2);
        expect(loaded.hasMore, isFalse);
      },
    );

    test('is a no-op when there is no next page', () async {
      when(
        () => repository.getOrders(
          page: 1,
          branchId: 74,
        ),
      ).thenAnswer(
        (_) async => OrderListPage(
          orders: [_order(1)],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );

      final built = buildAndStart(branch: branch74);
      await built.controller.initialization;
      await built.controller.loadMore();

      verifyNever(
        () => repository.getOrders(
          page: 2,
          branchId: 74,
        ),
      );
    });

    test(
      'a failed loadMore keeps the already-loaded orders and clears isLoadingMore',
      () async {
        when(
          () => repository.getOrders(
            page: 1,
            branchId: 74,
          ),
        ).thenAnswer(
          (_) async => OrderListPage(
            orders: [_order(1)],
            currentPage: 1,
            lastPage: 2,
            total: 2,
          ),
        );

        when(
          () => repository.getOrders(
            page: 2,
            branchId: 74,
          ),
        ).thenThrow(Exception('down'));

        final built = buildAndStart(branch: branch74);
        final controller = built.controller;
        final container = built.container;

        await controller.initialization;
        await controller.loadMore();

        final loaded =
            container.read(ordersListControllerProvider)
                as OrdersListLoaded;

        expect(loaded.orders, hasLength(1));
        expect(loaded.isLoadingMore, isFalse);
      },
    );
  });

  test('does not throw when the container is disposed mid-load', () async {
    when(
      () => repository.getOrders(
        page: 1,
        branchId: 74,
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(
        const Duration(milliseconds: 50),
      );

      return OrderListPage(
        orders: [_order(1)],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      );
    });

    final container = ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );

    final controller =
        container.read(ordersListControllerProvider.notifier);

    container.dispose();

    await expectLater(
      controller.initialization,
      completes,
    );
  });
}