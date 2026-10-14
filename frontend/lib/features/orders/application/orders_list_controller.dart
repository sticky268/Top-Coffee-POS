import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/orders_repository.dart';
import '../domain/orders_list_filters.dart';
import 'orders_list_state.dart';

/// Loads and filters the order history list.
class OrdersListController extends StateNotifier<OrdersListState> {
  int _generation = 0;
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
  OrdersListFilters _filters = OrdersListFilters.empty;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  /// Applies a new set of filters and reloads page 1.
  Future<void> applyFilters(OrdersListFilters filters) {
    _filters = filters;
    return refresh();
  }

  /// Clears all order filters and reloads page 1.
  Future<void> clearFilters() {
    _filters = OrdersListFilters.empty;
    return refresh();
  }

  /// Pull-to-refresh: reloads page 1 from scratch using the active filters.
  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!mounted || generation != _generation) return;

    state = const OrdersListLoading();

    try {
      final page = await _repository.getOrders(
        page: 1,
        branchId: _branchId,
        filters: _filters,
      );

      if (!mounted || generation != _generation) return;

      state = OrdersListLoaded(
        orders: page.orders,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        filters: _filters,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;

      state = OrdersListError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  /// Fetches the next page using the same active filters.
  Future<void> loadMore() async {
    final generation = _generation;
    final current = state;

    if (current is! OrdersListLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = await _repository.getOrders(
        page: current.currentPage + 1,
        branchId: _branchId,
        filters: current.filters,
      );

      if (!mounted || generation != _generation) return;

      final latest = state;

      if (latest is! OrdersListLoaded) return;

      state = latest.copyWith(
        orders: [...latest.orders, ...nextPage.orders],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;

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
