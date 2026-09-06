import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/products_repository.dart';
import '../domain/managed_product_models.dart';
import 'product_form_state.dart';

/// Handles the Add/Edit Product form's submit action. Unlike
/// PosCatalogController/AuthController, this controller does no work at
/// construction time (no auto-fetch — the form's initial values come from
/// the caller via ManagedProduct/ManagedProduct.fromPosProduct), so it
/// doesn't need the `initialization`-future pattern. `mounted` guards are
/// still applied around each await, for the same disposal-safety reason
/// as elsewhere.
///
/// autoDispose: a fresh controller each time the form screen is opened,
/// so a previous save's success/error doesn't leak into the next visit.
class ProductFormController extends StateNotifier<ProductFormState> {
  ProductFormController(this._repository) : super(const ProductFormIdle());

  final ProductsRepository _repository;

  Future<void> create(ManagedProduct product, {List<int> branchIds = const []}) async {
    if (!mounted) return;
    if (state is ProductFormSaving) return; // guards against double-submit
    state = const ProductFormSaving();

    try {
      final saved = await _repository.createProduct(product, branchIds: branchIds);
      if (!mounted) return;
      state = ProductFormSuccess(saved);
    } catch (e) {
      if (!mounted) return;
      state = ProductFormError(_messageFor(e));
    }
  }

  Future<void> update(int id, ManagedProduct product) async {
    if (!mounted) return;
    if (state is ProductFormSaving) return;
    state = const ProductFormSaving();

    try {
      final saved = await _repository.updateProduct(id, product);
      if (!mounted) return;
      state = ProductFormSuccess(saved);
    } catch (e) {
      if (!mounted) return;
      state = ProductFormError(_messageFor(e));
    }
  }

  String _messageFor(Object e) {
    if (e is ValidationException) {
      final first = e.errors.values.isNotEmpty ? e.errors.values.first : null;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first != null) return first.toString();
      return e.message;
    }
    if (e is ApiException) return e.message;
    return 'Something went wrong';
  }
}

final productFormControllerProvider =
    StateNotifierProvider.autoDispose<ProductFormController, ProductFormState>((ref) {
  return ProductFormController(ref.watch(productsRepositoryProvider));
});
