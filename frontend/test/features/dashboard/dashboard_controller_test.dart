import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/dashboard/application/dashboard_controller.dart';
import 'package:top_coffee_pos/features/dashboard/application/dashboard_state.dart';
import 'package:top_coffee_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:top_coffee_pos/features/dashboard/domain/dashboard_models.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

const _stats = DashboardStats(
  todaysSales: 1248.50,
  todaysOrders: 86,
  averageOrderValue: 14.52,
  lowStockItemCount: 5,
);

final _order = RecentOrder(
  orderNumber: '#1042',
  time: DateTime(2026, 1, 1, 9, 30),
  customerOrTable: 'Table 4',
  itemCount: 3,
  total: 15.40,
  status: OrderStatus.preparing,
);

final _salesPoint = SalesDataPoint(date: DateTime(2026, 1, 1), total: 500);

void main() {
  late MockDashboardRepository repository;

  setUp(() {
    repository = MockDashboardRepository();
  });

  /// Same pattern established for AuthController in Phase 3: reading
  /// `.notifier` forces the (lazy) provider to construct immediately,
  /// and `initialization` is a deterministic completion signal — no
  /// guessing with delays.
  ({ProviderContainer container, DashboardController controller}) buildAndStart() {
    final container = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(dashboardControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  test('starts in Loading immediately after construction', () {
    when(() => repository.getStats()).thenAnswer((_) async => _stats);
    when(() => repository.getRecentOrders()).thenAnswer((_) async => [_order]);
    when(() => repository.getSalesOverview()).thenAnswer((_) async => [_salesPoint]);

    final built = buildAndStart();

    expect(built.container.read(dashboardControllerProvider), isA<DashboardLoading>());
  });

  test('loads successfully into DashboardLoaded with the fetched data', () async {
    when(() => repository.getStats()).thenAnswer((_) async => _stats);
    when(() => repository.getRecentOrders()).thenAnswer((_) async => [_order]);
    when(() => repository.getSalesOverview()).thenAnswer((_) async => [_salesPoint]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(dashboardControllerProvider);
    expect(state, isA<DashboardLoaded>());
    final loaded = state as DashboardLoaded;
    expect(loaded.stats.todaysOrders, 86);
    expect(loaded.recentOrders, hasLength(1));
    expect(loaded.salesOverview, hasLength(1));
  });

  test('a repository failure results in DashboardError, never a stuck Loading', () async {
    when(() => repository.getStats()).thenThrow(Exception('network down'));
    when(() => repository.getRecentOrders()).thenAnswer((_) async => [_order]);
    when(() => repository.getSalesOverview()).thenAnswer((_) async => [_salesPoint]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(dashboardControllerProvider);
    expect(state, isNot(isA<DashboardLoading>()));
    expect(state, isA<DashboardError>());
  });

  test('refresh() re-fetches and can recover from a prior error', () async {
    when(() => repository.getStats()).thenThrow(Exception('network down'));
    when(() => repository.getRecentOrders()).thenAnswer((_) async => [_order]);
    when(() => repository.getSalesOverview()).thenAnswer((_) async => [_salesPoint]);

    final built = buildAndStart();
    await built.controller.initialization;
    expect(built.container.read(dashboardControllerProvider), isA<DashboardError>());

    when(() => repository.getStats()).thenAnswer((_) async => _stats);
    await built.controller.refresh();

    expect(built.container.read(dashboardControllerProvider), isA<DashboardLoaded>());
  });

  test('does not throw when the container is disposed mid-load', () async {
    when(() => repository.getStats()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _stats;
    });
    when(() => repository.getRecentOrders()).thenAnswer((_) async => [_order]);
    when(() => repository.getSalesOverview()).thenAnswer((_) async => [_salesPoint]);

    final container = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(dashboardControllerProvider.notifier);

    container.dispose(); // dispose while getStats() is still in flight

    await expectLater(controller.initialization, completes);
  });
}
