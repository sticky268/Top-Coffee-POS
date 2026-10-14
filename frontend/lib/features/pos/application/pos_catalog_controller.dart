import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/pos_repository.dart';
import 'pos_catalog_state.dart';

/// Loads categories + products on construction and exposes
/// [PosCatalogState]. Deliberately separate from cart state (see
/// CartController) — reloading/erroring the catalog must never touch
/// an in-progress cart.
///
/// Follows the same two guarantees established for AuthController (Phase
/// 3) and DashboardController (Phase 4):
///  1. [initialization] is a deterministic completion signal — tests
///     should await it instead of guessing with delays, since Riverpod
///     providers are lazy.
///  2. Every `state = ...` after an `await` is guarded by [mounted].
class PosCatalogController extends StateNotifier<PosCatalogState> {
  PosCatalogController(this._repository, this._ref)
      : super(const PosCatalogLoading()) {
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

  final PosRepository _repository;
  final Ref _ref;

  int? _branchId;
  int _generation = 0;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    final branchId = _branchId;
    _ref.read(cachedCatalogProvider.notifier).state = false;
    state = const PosCatalogLoading();

    try {
      final results = await Future.wait<dynamic>([
        _repository.getCategories(branchId: branchId),
        _repository.getProducts(branchId: branchId),
      ]);
      if (!mounted || generation != _generation) return;

      state = PosCatalogLoaded(
        categories: results[0],
        products: results[1],
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;

      state = PosCatalogError(
        e is ApiException ? e.message : 'Something went wrong',
      );
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

final posCatalogControllerProvider =
    StateNotifierProvider<PosCatalogController, PosCatalogState>((ref) {
  return PosCatalogController(
    ref.watch(posRepositoryProvider),
    ref,
  );
});
