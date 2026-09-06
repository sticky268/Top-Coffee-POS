import '../domain/dashboard_models.dart';

sealed class DashboardState {
  const DashboardState();
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.stats,
    required this.recentOrders,
    required this.salesOverview,
  });

  final DashboardStats stats;
  final List<RecentOrder> recentOrders;
  final List<SalesDataPoint> salesOverview;
}

class DashboardError extends DashboardState {
  const DashboardError(this.message);
  final String message;
}
