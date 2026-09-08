import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/orders_repository.dart';
import 'orders_list_state.dart';

/// Loads page 1 of orders on construction and exposes [OrdersListState].
/// Follows the same mounted-guard + deterministic `initialization` future
/// pattern established for every other controller in this codebase
/// (AuthController, DashboardController, PosCatalogController).
class OrdersListController extends StateNotifier<OrdersListState> {
  OrdersListController(this._repository, this._ref)
      : super(const OrdersListLoading()) {
    _branchId = _ref.read(currentBranchProvider)?.id;

    _ref.listen(
      currentBranchProvider,
      (_, next) {
        final nextBranchId = next?.id;

        if (_branchId == nextBranchId) {
          return;
        }

        _branchId = nextBranchId;
        refresh();
      },
    );

    _initialization = _load();
  }

  final OrdersRepository _repository;
  final Ref _ref;

  int? _branchId;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  /// Pull-to-refresh: reloads page 1 from scratch.
  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    state = const OrdersListLoading();

    try {
      final page = await _repository.getOrders(
        page: 1,
        branchId: _branchId,
      );

      if (!mounted) return;

      state = OrdersListLoaded(
        orders: page.orders,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
      );
  } catch (e) {

    if (!mounted) return;
    state = OrdersListError(
      e is ApiException ? e.message : 'Something went wrong',
    );
  }
  }

  /// Fetches the next page and appends it — a no-op if already loading,
  /// already on the last page, or the list isn't in a loaded state.
  Future<void> loadMore() async {
    final current = state;

    if (current is! OrdersListLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = await _repository.getOrders(
        page: current.currentPage + 1,
        branchId: _branchId,
      );

      if (!mounted) return;

      final latest = state;

      if (latest is! OrdersListLoaded) return;

      state = latest.copyWith(
        orders: [...latest.orders, ...nextPage.orders],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;

      final latest = state;

      if (latest is OrdersListLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}

final ordersListControllerProvider =
    StateNotifierProvider<OrdersListController, OrdersListState>((ref) {
  return OrdersListController(
    ref.watch(ordersRepositoryProvider),
    ref,
  );
});