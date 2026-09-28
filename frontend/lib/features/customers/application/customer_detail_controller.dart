import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/customers_repository.dart';
import '../domain/customer_models.dart';
import 'customer_detail_state.dart';

class CustomerDetailController
    extends StateNotifier<CustomerDetailState> {
  CustomerDetailController(
    this._repository,
    this._customerId,
  ) : super(const CustomerDetailLoading()) {
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

    state = const CustomerDetailLoading();

    try {
      final customer = await _repository.getCustomer(_customerId);

      if (!mounted) return;

      state = CustomerDetailLoaded(
        customer: customer,
      );
    } catch (e) {
      if (!mounted) return;

      state = CustomerDetailError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<Customer?> updateCustomer({
    String? name,
    String? phone,
    String? email,
    String? notes,
  }) async {
    try {
      final customer = await _repository.updateCustomer(
        id: _customerId,
        name: name,
        phone: phone,
        email: email,
        notes: notes,
      );

      if (!mounted) return customer;

      state = CustomerDetailLoaded(
        customer: customer,
      );

      return customer;
    } catch (e) {
      if (!mounted) return null;

      state = CustomerDetailError(
        e is ApiException ? e.message : 'Something went wrong',
      );

      return null;
    }
  }

  Future<bool> deleteCustomer() async {
    try {
      await _repository.deleteCustomer(_customerId);
      return true;
    } catch (e) {
      if (!mounted) return false;

      state = CustomerDetailError(
        e is ApiException ? e.message : 'Something went wrong',
      );

      return false;
    }
  }
}

final customerDetailControllerProvider = StateNotifierProvider.family<
    CustomerDetailController,
    CustomerDetailState,
    int>((ref, customerId) {
  return CustomerDetailController(
    ref.watch(customersRepositoryProvider),
    customerId,
  );
});
