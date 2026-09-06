import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/products_repository.dart';
import 'products_state.dart';

/// Loads categories + products for the standalone Products browsing
/// screen. Deliberately an INDEPENDENT provider/controller from
/// PosCatalogController, despite the near-identical shape — sharing that
/// provider instance would mean filtering products on this screen also
/// changes what the POS ordering screen shows (and vice versa), since
/// Riverpod providers are singletons. Two different screens with two
/// different purposes must not share one filter/selection state.
///
/// Same mounted-guard + deterministic `initialization` future pattern as
/// every other controller in this codebase.
class ProductsController extends StateNotifier<ProductsState> {
  ProductsController(this._repository) : super(const ProductsLoading()) {
    _initialization = _load();
  }

  final ProductsRepository _repository;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    state = const ProductsLoading();

    try {
      final categoriesFuture = _repository.getCategories();
      final productsFuture = _repository.getProducts();

      final categories = await categoriesFuture;
      final products = await productsFuture;
      if (!mounted) return;

      state = ProductsLoaded(categories: categories, products: products);
    } catch (e) {
      if (!mounted) return;
      state = ProductsError(e is ApiException ? e.message : 'Something went wrong');
    }
  }

  void selectCategory(int? categoryId) {
    final current = state;
    if (current is! ProductsLoaded) return;
    state = ProductsLoaded(
      categories: current.categories,
      products: current.products,
      selectedCategoryId: categoryId,
      searchQuery: current.searchQuery,
    );
  }

  void updateSearchQuery(String query) {
    final current = state;
    if (current is! ProductsLoaded) return;
    state = ProductsLoaded(
      categories: current.categories,
      products: current.products,
      selectedCategoryId: current.selectedCategoryId,
      searchQuery: query,
    );
  }
}

final productsControllerProvider = StateNotifierProvider<ProductsController, ProductsState>((ref) {
  return ProductsController(ref.watch(productsRepositoryProvider));
});
