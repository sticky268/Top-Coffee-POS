import '../../pos/domain/pos_models.dart';

sealed class ProductsState {
  const ProductsState();
}

class ProductsLoading extends ProductsState {
  const ProductsLoading();
}

class ProductsLoaded extends ProductsState {
  const ProductsLoaded({
    required this.categories,
    required this.products,
    this.selectedCategoryId,
    this.searchQuery = '',
  });

  final List<PosCategory> categories;
  final List<PosProduct> products;

  /// null = "All" selected.
  final int? selectedCategoryId;
  final String searchQuery;

  bool get isFiltered => selectedCategoryId != null || searchQuery.trim().isNotEmpty;

  /// [products] filtered by category and/or search, computed locally — no
  /// second API request per tap or keystroke (the backend has no search
  /// parameter — confirmed by reading ProductController::index() before
  /// building this).
  List<PosProduct> get visibleProducts {
    var result = products;

    if (selectedCategoryId != null) {
      result = result.where((p) => p.category?.id == selectedCategoryId).toList();
    }

    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((p) => p.name.toLowerCase().contains(query)).toList();
    }

    return result;
  }
}

class ProductsError extends ProductsState {
  const ProductsError(this.message);
  final String message;
}
