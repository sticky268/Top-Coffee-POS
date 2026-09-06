import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/pos_repository.dart';
import 'pos_catalog_state.dart';

/// Loads categories + products on construction and exposes
/// [PosCatalogState]. Deliberately separate from cart state (see
/// CartController) — reloading/erroring the catalog must never touch an
/// in-progress cart.
///
/// Follows the same two guarantees established for AuthController (Phase
/// 3) and DashboardController (Phase 4):
///  1. [initialization] is a deterministic completion signal — tests
///     should await it instead of guessing with delays, since Riverpod
///     providers are lazy.
///  2. Every `state = ...` after an `await` is guarded by [mounted].
class PosCatalogController extends StateNotifier<PosCatalogState> {
  PosCatalogController(this._repository) : super(const PosCatalogLoading()) {
    _initialization = _load();
  }

  final PosRepository _repository;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    state = const PosCatalogLoading();

    try {
      final categoriesFuture = _repository.getCategories();
      final productsFuture = _repository.getProducts();

      final categories = await categoriesFuture;
      final products = await productsFuture;
      if (!mounted) return;

      state = PosCatalogLoaded(categories: categories, products: products);
    } catch (e) {
      if (!mounted) return;
      // Extract .message explicitly rather than e.toString() — an
      // ApiException's default toString() is just "Instance of
      // 'NetworkException'" etc, not the human-readable message.
      state = PosCatalogError(e is ApiException ? e.message : 'Something went wrong');
    }
  }

  /// Switches the locally-filtered category tab. No-ops if the catalog
  /// isn't loaded yet (e.g. a stray tap during a retry).
  void selectCategory(int? categoryId) {
    final current = state;
    if (current is! PosCatalogLoaded) return;
    state = PosCatalogLoaded(
      categories: current.categories,
      products: current.products,
      selectedCategoryId: categoryId,
      searchQuery: current.searchQuery,
    );
  }

  /// Updates the local product-name search filter. Same no-op guard as
  /// selectCategory — and combines with whatever category is currently
  /// selected rather than resetting it.
  void updateSearchQuery(String query) {
    final current = state;
    if (current is! PosCatalogLoaded) return;
    state = PosCatalogLoaded(
      categories: current.categories,
      products: current.products,
      selectedCategoryId: current.selectedCategoryId,
      searchQuery: query,
    );
  }
}

final posCatalogControllerProvider = StateNotifierProvider<PosCatalogController, PosCatalogState>((ref) {
  return PosCatalogController(ref.watch(posRepositoryProvider));
});
