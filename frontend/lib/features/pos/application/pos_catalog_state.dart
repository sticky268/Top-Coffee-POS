import '../domain/pos_models.dart';

sealed class PosCatalogState {
  const PosCatalogState();
}

class PosCatalogLoading extends PosCatalogState {
  const PosCatalogLoading();
}

class PosCatalogLoaded extends PosCatalogState {
  const PosCatalogLoaded({
    required this.categories,
    required this.products,
    this.selectedCategoryId,
    this.searchQuery = '',
  });

  final List<PosCategory> categories;
  final List<PosProduct> products;

  /// null = "All" selected.
  final int? selectedCategoryId;

  /// Case-insensitive substring match against product name.
  final String searchQuery;

  /// [products] filtered by [selectedCategoryId] AND [searchQuery], both
  /// computed locally — no second API request per category tap or
  /// keystroke (see PosRepository.getProducts).
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

class PosCatalogError extends PosCatalogState {
  const PosCatalogError(this.message);
  final String message;
}
