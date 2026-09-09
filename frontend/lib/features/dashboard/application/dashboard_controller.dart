import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

/// Loads dashboard data on construction and reloads automatically when the
/// selected branch changes.
class DashboardController extends StateNotifier<DashboardState> {
  DashboardController(this._repository, this._ref)
      : super(const DashboardLoading()) {
    _ref.listen(
      currentBranchProvider,
      (_, __) => refresh(),
    );

    _initialization = _load();
  }

  final DashboardRepository _repository;
  final Ref _ref;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  /// Re-fetches everything (pull-to-refresh / retry-after-error).
  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    state = const DashboardLoading();

    try {
      final statsFuture = _repository.getStats();
      final ordersFuture = _repository.getRecentOrders();
      final salesFuture = _repository.getSalesOverview();

      final stats = await statsFuture;
      final orders = await ordersFuture;
      final sales = await salesFuture;

      if (!mounted) return;

      state = DashboardLoaded(
        stats: stats,
        recentOrders: orders,
        salesOverview: sales,
      );
    } catch (e) {
      if (!mounted) return;
      state = DashboardError(e.toString());
    }
  }
}

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
  return DashboardController(
    ref.watch(dashboardRepositoryProvider),
    ref,
  );
});
