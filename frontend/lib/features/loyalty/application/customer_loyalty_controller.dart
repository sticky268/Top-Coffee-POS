import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/loyalty_repository.dart';
import 'customer_loyalty_state.dart';

class CustomerLoyaltyController
    extends StateNotifier<CustomerLoyaltyState> {
  CustomerLoyaltyController(
    this._repository,
    this._customerId,
  ) : super(const CustomerLoyaltyLoading()) {
    _initialization = _load();
  }

  final LoyaltyRepository _repository;
  final int _customerId;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load({
    int page = 1,
  }) async {
    if (!mounted) return;

    state = const CustomerLoyaltyLoading();

    try {
      final loyalty = await _repository.getCustomerLoyalty(
        customerId: _customerId,
        page: page,
      );

      if (!mounted) return;

      state = CustomerLoyaltyLoaded(
        loyalty: loyalty,
      );
    } catch (e) {
      if (!mounted) return;

      state = CustomerLoyaltyError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<bool> adjustPoints({
    required int points,
    String? description,
    int? branchId,
  }) async {
    try {
      await _repository.adjustCustomerLoyalty(
        customerId: _customerId,
        points: points,
        description: description,
        branchId: branchId,
      );

      await _load();

      return state is CustomerLoyaltyLoaded;
    } catch (e) {
      if (!mounted) return false;

      state = CustomerLoyaltyError(
        e is ApiException ? e.message : 'Something went wrong',
      );

      return false;
    }
  }
}

final customerLoyaltyControllerProvider = StateNotifierProvider.autoDispose.family<
    CustomerLoyaltyController,
    CustomerLoyaltyState,
    int>((ref, customerId) {
  return CustomerLoyaltyController(
    ref.watch(loyaltyRepositoryProvider),
    customerId,
  );
});
