import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

class InventoryListState {
  const InventoryListState({
    this.ingredients = const [],
    this.isLoading = false,
    this.errorMessage,
    this.scope,
  });

  final List<InventoryIngredient> ingredients;
  final bool isLoading;
  final String? errorMessage;
  final InventoryScope? scope;

  InventoryListState copyWith({
    List<InventoryIngredient>? ingredients,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return InventoryListState(
      ingredients: ingredients ?? this.ingredients,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      scope: scope,
    );
  }
}

typedef InventoryScope = ({int userId, int branchId});

/// Inventory always belongs to the selected, authorized branch.
final inventoryScopeProvider = Provider<InventoryScope?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final branch = ref.watch(currentBranchProvider);
  if (auth is! AuthAuthenticated ||
      branch == null ||
      !auth.user.hasPermission('inventory.view') ||
      (!auth.user.hasPermission('branches.view-all') &&
          !auth.user.branches.any((item) => item.id == branch.id))) {
    return null;
  }
  return (userId: auth.user.id, branchId: branch.id);
});

class InventoryListController extends AsyncNotifier<InventoryListState> {
  @override
  Future<InventoryListState> build() async {
    final scope = ref.watch(inventoryScopeProvider);
    if (scope == null) {
      throw StateError('Select a branch you can view before opening inventory.');
    }
    final repository = ref.watch(inventoryRepositoryProvider);
    final ingredients = await repository.getIngredients(branchId: scope.branchId);
    return InventoryListState(ingredients: ingredients, scope: scope);
  }

  Future<void> refresh() async {
    // Rebuild through Riverpod so a response for a previous session or branch
    // cannot replace the active branch after an overlapping refresh.
    ref.invalidateSelf();
    await future;
  }
}

final inventoryListControllerProvider =
    AsyncNotifierProvider<InventoryListController, InventoryListState>(
  InventoryListController.new,
);