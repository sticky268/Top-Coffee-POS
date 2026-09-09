import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/products_repository.dart';
import '../domain/managed_product_models.dart';
import 'product_form_state.dart';

class ProductFormController extends StateNotifier<ProductFormState> {
  ProductFormController(this._repository) : super(const ProductFormIdle());

  final ProductsRepository _repository;

  Future<void> create(
    ManagedProduct product, {
    List<int> branchIds = const [],
    XFile? imageFile,
  }) async {
    if (!mounted) return;
    if (state is ProductFormSaving) return;

    state = const ProductFormSaving();

    try {
      final saved = await _repository.createProduct(
        product,
        branchIds: branchIds,
        imageFile: imageFile,
      );

      if (!mounted) return;
      state = ProductFormSuccess(saved);
    } catch (e) {
      if (!mounted) return;
      state = ProductFormError(_messageFor(e));
    }
  }

  Future<void> update(
    int id,
    ManagedProduct product, {
    XFile? imageFile,
  }) async {
    if (!mounted) return;
    if (state is ProductFormSaving) return;

    state = const ProductFormSaving();

    try {
      final saved = await _repository.updateProduct(
        id,
        product,
        imageFile: imageFile,
      );

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
    StateNotifierProvider.autoDispose<ProductFormController, ProductFormState>(
  (ref) {
    return ProductFormController(ref.watch(productsRepositoryProvider));
  },
);