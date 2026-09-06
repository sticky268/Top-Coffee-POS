import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/orders_repository.dart';
import 'orders_list_state.dart';

/// Loads page 1 of orders on construction and exposes [OrdersListState].
/// Follows the same mounted-guard + deterministic `initialization` future
/// pattern established for every other controller in this codebase
/// (AuthController, DashboardController, PosCatalogController).
class OrdersListController extends StateNotifier<OrdersListState> {
  OrdersListController(this._repository) : super(const OrdersListLoading()) {
    _initialization = _load();
  }

  final OrdersRepository _repository;
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
      final page = await _repository.getOrders(page: 1);
      if (!mounted) return;
      state = OrdersListLoaded(
        orders: page.orders,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
      );
    } catch (e) {
      if (!mounted) return;
      state = OrdersListError(e is ApiException ? e.message : 'Something went wrong');
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
      final nextPage = await _repository.getOrders(page: current.currentPage + 1);
      if (!mounted) return;

      final latest = state;
      if (latest is! OrdersListLoaded) return; // a refresh() raced in and replaced state — drop this page

      state = latest.copyWith(
        orders: [...latest.orders, ...nextPage.orders],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        isLoadingMore: false,
      );
    } catch (_) {
      // A failed "load more" must not blow away the already-loaded list —
      // just clear the loading-more flag so the user can retry by
      // scrolling again (or pull-to-refresh).
      if (!mounted) return;
      final latest = state;
      if (latest is OrdersListLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}

final ordersListControllerProvider = StateNotifierProvider<OrdersListController, OrdersListState>((ref) {
  return OrdersListController(ref.watch(ordersRepositoryProvider));
});
