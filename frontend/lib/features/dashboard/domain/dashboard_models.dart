/// Domain models for the POS dashboard. Deliberately framework-agnostic
/// (no Flutter imports) — the same convention used by features/auth/domain.
/// Presentation-only concerns (colors, icons) live in the presentation layer.
library;

/// The four headline stat-card values shown at the top of the dashboard.
class DashboardStats {
  const DashboardStats({
    required this.todaysSales,
    required this.todaysOrders,
    required this.averageOrderValue,
    required this.lowStockItemCount,
  });

  final double todaysSales;
  final int todaysOrders;
  final double averageOrderValue;
  final int lowStockItemCount;
}

enum OrderStatus { pending, preparing, ready, completed, cancelled }

class RecentOrder {
  const RecentOrder({
    required this.orderNumber,
    required this.time,
    required this.itemCount,
    required this.total,
    required this.status,
    this.customerOrTable,
  });

  final String orderNumber;
  final DateTime time;
  final String? customerOrTable;
  final int itemCount;
  final double total;
  final OrderStatus status;
}

/// One day's total in the 7-day sales overview.
class SalesDataPoint {
  const SalesDataPoint({required this.date, required this.total});

  final DateTime date;
  final double total;
}
