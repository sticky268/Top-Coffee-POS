import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../domain/dashboard_models.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

/// Loads dashboard data on construction and reloads automatically when the
/// selected branch changes.
class DashboardController extends StateNotifier<DashboardState> {
  DashboardController(this._repository, this._ref)
    : super(const DashboardLoading()) {
    _ref.listen(currentBranchProvider, (_, __) => refresh());

    _initialization = _load();
  }

  final DashboardRepository _repository;
  final Ref _ref;
  late Future<void> _initialization;
  int _generation = 0;

  Future<void> get initialization => _initialization;

  /// Re-fetches everything (pull-to-refresh / retry-after-error).
  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    state = const DashboardLoading();

    try {
      // Attach an error handler to every request immediately. Sequentially
      // awaiting already-started futures leaves later failures unhandled.
      // Future.sync also brings synchronous repository throws into the batch.
      final results = await Future.wait<Object>([
        Future.sync(_repository.getStats),
        Future.sync(_repository.getRecentOrders),
        Future.sync(_repository.getSalesOverview),
      ]);

      if (!mounted || generation != _generation) return;

      state = DashboardLoaded(
        stats: results[0] as DashboardStats,
        recentOrders: results[1] as List<RecentOrder>,
        salesOverview: results[2] as List<SalesDataPoint>,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = DashboardError(e is ApiException ? e.message : e.toString());
    }
  }
}

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
      return DashboardController(ref.watch(dashboardRepositoryProvider), ref);
    });
