import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/supplier_repository.dart';
import 'supplier_list_state.dart';

class SupplierListController extends StateNotifier<SupplierListState> {
  SupplierListController(this._repository, this._ref)
      : super(const SupplierListLoading()) {
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

  final PurchaseSupplierRepository _repository;
  final Ref _ref;

  int? _branchId;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const SupplierListLoading();

    try {
      final suppliers = await _repository.getSuppliers(
        branchId: _branchId,
      );

      if (!mounted) return;

      state = SupplierListLoaded(
        suppliers: suppliers,
      );
    } catch (e) {
      if (!mounted) return;

      state = SupplierListError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }
}

final supplierListControllerProvider =
    StateNotifierProvider<SupplierListController, SupplierListState>((ref) {
  return SupplierListController(
    ref.watch(purchaseSupplierRepositoryProvider),
    ref,
  );
});
