import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/orders_repository.dart';
import 'order_detail_state.dart';

/// Loads a single order's detail on construction. Same mounted-guard +
/// deterministic `initialization` pattern as every other controller here.
///
/// Parametrized by order id via Riverpod's `.family` modifier — the
/// standard, already-available way to scope a provider to an argument;
/// not a new state-management pattern. `.autoDispose` so a previously
/// viewed order's state doesn't linger in memory once its detail screen
/// is popped.
class OrderDetailController extends StateNotifier<OrderDetailState> {
  OrderDetailController(this._repository, this._orderId) : super(const OrderDetailLoading()) {
    _initialization = _load();
  }

  final OrdersRepository _repository;
  final int _orderId;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    state = const OrderDetailLoading();

    try {
      final order = await _repository.getOrder(_orderId);
      if (!mounted) return;
      state = OrderDetailLoaded(order);
    } catch (e) {
      if (!mounted) return;
      state = OrderDetailError(e is ApiException ? e.message : 'Something went wrong');
    }
  }
}

final orderDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<OrderDetailController, OrderDetailState, int>((ref, orderId) {
  return OrderDetailController(ref.watch(ordersRepositoryProvider), orderId);
});
