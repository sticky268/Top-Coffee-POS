import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/customers_repository.dart';
import 'customer_orders_state.dart';

class CustomerOrdersController
    extends StateNotifier<CustomerOrdersState> {
  CustomerOrdersController(
    this._repository,
    this._customerId,
  ) : super(const CustomerOrdersLoading()) {
    _initialization = _load();
  }

  final CustomersRepository _repository;
  final int _customerId;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const CustomerOrdersLoading();

    try {
      final page = await _repository.getCustomerOrders(
        customerId: _customerId,
        page: 1,
      );

      if (!mounted) return;

      state = CustomerOrdersLoaded(
        orders: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;

      state = CustomerOrdersError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! CustomerOrdersLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = await _repository.getCustomerOrders(
        customerId: _customerId,
        page: current.currentPage + 1,
      );

      if (!mounted) return;

      final latest = state;

      if (latest is! CustomerOrdersLoaded) return;

      state = latest.copyWith(
        orders: [...latest.orders, ...nextPage.data],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        total: nextPage.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;

      final latest = state;

      if (latest is CustomerOrdersLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}

final customerOrdersControllerProvider = StateNotifierProvider.family<
    CustomerOrdersController,
    CustomerOrdersState,
    int>((ref, customerId) {
  return CustomerOrdersController(
    ref.watch(customersRepositoryProvider),
    customerId,
  );
});
