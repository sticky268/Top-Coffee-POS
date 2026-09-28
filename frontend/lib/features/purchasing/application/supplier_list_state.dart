import '../domain/purchase_models.dart';

sealed class SupplierListState {
  const SupplierListState();
}

class SupplierListLoading extends SupplierListState {
  const SupplierListLoading();
}

class SupplierListLoaded extends SupplierListState {
  const SupplierListLoaded({
    required this.suppliers,
  });

  final List<PurchaseSupplier> suppliers;
}

class SupplierListError extends SupplierListState {
  const SupplierListError(this.message);

  final String message;
}
