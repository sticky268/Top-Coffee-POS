import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

/// Loads dashboard data on construction and exposes [DashboardState].
///
/// Follows the same two guarantees established for AuthController in
/// Phase 3 (see auth_controller.dart for the full rationale):
///  1. [initialization] is a deterministic completion signal — tests (and
///     any future startup-gating code) should await it instead of guessing
///     with delays, since Riverpod providers are lazy.
///  2. Every `state = ...` after an `await` is guarded by [mounted], so a
///     disposed controller can never throw or leak a late update.
class DashboardController extends StateNotifier<DashboardState> {
  DashboardController(this._repository) : super(const DashboardLoading()) {
    _initialization = _load();
  }

  final DashboardRepository _repository;
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
      // Started concurrently (not one `await` per line) so the three calls
      // race in parallel, same latency as a single request — the `as
      // dynamic` casts a combined Future.wait<Object> list would otherwise
      // need are avoided by awaiting each typed Future separately.
      final statsFuture = _repository.getStats();
      final ordersFuture = _repository.getRecentOrders();
      final salesFuture = _repository.getSalesOverview();

      final stats = await statsFuture;
      final orders = await ordersFuture;
      final sales = await salesFuture;
      if (!mounted) return;

      state = DashboardLoaded(stats: stats, recentOrders: orders, salesOverview: sales);
    } catch (e) {
      if (!mounted) return;
      state = DashboardError(e.toString());
    }
  }
}

final dashboardControllerProvider = StateNotifierProvider<DashboardController, DashboardState>((ref) {
  return DashboardController(ref.watch(dashboardRepositoryProvider));
});
