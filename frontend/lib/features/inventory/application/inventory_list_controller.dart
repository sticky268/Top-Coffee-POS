import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

class InventoryListState {
  const InventoryListState({
    this.ingredients = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<InventoryIngredient> ingredients;
  final bool isLoading;
  final String? errorMessage;

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
    );
  }
}

class InventoryListController extends AsyncNotifier<InventoryListState> {
  @override
  Future<InventoryListState> build() async {
    return _load();
  }

  Future<InventoryListState> _load() async {
    final repository = ref.read(inventoryRepositoryProvider);

    final ingredients = await repository.getIngredients();

    return InventoryListState(
      ingredients: ingredients,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      return _load();
    });
  }
}

final inventoryListControllerProvider =
    AsyncNotifierProvider<InventoryListController, InventoryListState>(
  InventoryListController.new,
);