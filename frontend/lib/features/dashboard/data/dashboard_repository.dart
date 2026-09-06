import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dashboard_models.dart';

/// Data boundary for the dashboard. [DashboardController] depends only on
/// this interface, so swapping [LocalDashboardRepository] for a real
/// `ApiDashboardRepository` (backed by GET /api/v1/dashboard, once the
/// backend builds it in a later phase) is a one-line change at
/// [dashboardRepositoryProvider] — nothing above this layer needs to know.
abstract class DashboardRepository {
  Future<DashboardStats> getStats();
  Future<List<RecentOrder>> getRecentOrders({int limit = 5});
  Future<List<SalesDataPoint>> getSalesOverview({int days = 7});
}

/// Local data source for the initial dashboard implementation. Simulates
/// realistic network latency so loading states are visible and testable,
/// and is the only place with example values — nothing is hardcoded into
/// the controller or UI layers. Named "Local" (not "Mock") because this is
/// production code, not a test double — mocktail's `MockDashboardRepository`
/// test class is a separate, unrelated type.
class LocalDashboardRepository implements DashboardRepository {
  LocalDashboardRepository({this.simulatedLatency = const Duration(milliseconds: 400)});

  final Duration simulatedLatency;

  @override
  Future<DashboardStats> getStats() async {
    await Future.delayed(simulatedLatency);
    return const DashboardStats(
      todaysSales: 1248.50,
      todaysOrders: 86,
      averageOrderValue: 14.52,
      lowStockItemCount: 5,
    );
  }

  @override
  Future<List<RecentOrder>> getRecentOrders({int limit = 5}) async {
    await Future.delayed(simulatedLatency);
    final now = DateTime.now();
    final orders = [
      RecentOrder(
        orderNumber: '#1042',
        time: now.subtract(const Duration(minutes: 3)),
        customerOrTable: 'Table 4',
        itemCount: 3,
        total: 15.40,
        status: OrderStatus.preparing,
      ),
      RecentOrder(
        orderNumber: '#1041',
        time: now.subtract(const Duration(minutes: 9)),
        customerOrTable: 'Takeaway',
        itemCount: 1,
        total: 3.50,
        status: OrderStatus.ready,
      ),
      RecentOrder(
        orderNumber: '#1040',
        time: now.subtract(const Duration(minutes: 14)),
        customerOrTable: 'Table 2',
        itemCount: 2,
        total: 9.25,
        status: OrderStatus.completed,
      ),
      RecentOrder(
        orderNumber: '#1039',
        time: now.subtract(const Duration(minutes: 22)),
        customerOrTable: 'Takeaway',
        itemCount: 4,
        total: 21.80,
        status: OrderStatus.completed,
      ),
      RecentOrder(
        orderNumber: '#1038',
        time: now.subtract(const Duration(minutes: 30)),
        customerOrTable: 'Table 7',
        itemCount: 2,
        total: 7.00,
        status: OrderStatus.cancelled,
      ),
      RecentOrder(
        orderNumber: '#1037',
        time: now.subtract(const Duration(minutes: 41)),
        customerOrTable: null,
        itemCount: 1,
        total: 2.75,
        status: OrderStatus.pending,
      ),
    ];
    return orders.take(limit).toList();
  }

  @override
  Future<List<SalesDataPoint>> getSalesOverview({int days = 7}) async {
    await Future.delayed(simulatedLatency);
    final today = DateTime.now();
    final values = [420.0, 610.0, 380.0, 705.5, 890.0, 1120.25, 1248.50];
    return List.generate(days, (i) {
      final offset = days - 1 - i;
      return SalesDataPoint(
        date: today.subtract(Duration(days: offset)),
        total: values[i % values.length],
      );
    });
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return LocalDashboardRepository();
});
