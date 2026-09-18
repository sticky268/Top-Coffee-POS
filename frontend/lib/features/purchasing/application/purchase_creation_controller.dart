import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../data/purchase_repository.dart';
import '../domain/purchase_models.dart';

class PurchaseDraftItem {
  const PurchaseDraftItem({
    required this.ingredientId,
    this.quantity = 0,
    this.unitCost = 0,
  });

  final int ingredientId;
  final double quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;

  PurchaseDraftItem copyWith({
    double? quantity,
    double? unitCost,
  }) {
    return PurchaseDraftItem(
      ingredientId: ingredientId,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
    );
  }

  PurchaseCreateItem toCreateItem() {
    return PurchaseCreateItem(
      ingredientId: ingredientId,
      quantity: quantity,
      unitCost: unitCost,
    );
  }
}

class PurchaseCreationState {
  const PurchaseCreationState({
    required this.supplierId,
    required this.purchasedAt,
    required this.items,
    this.isSaving = false,
  });

  final int? supplierId;
  final DateTime purchasedAt;
  final List<PurchaseDraftItem> items;
  final bool isSaving;

  double get totalCost {
    return items.fold(
      0,
      (total, item) => total + item.lineTotal,
    );
  }

  PurchaseCreationState copyWith({
    int? supplierId,
    bool clearSupplier = false,
    DateTime? purchasedAt,
    List<PurchaseDraftItem>? items,
    bool? isSaving,
  }) {
    return PurchaseCreationState(
      supplierId: clearSupplier ? null : supplierId ?? this.supplierId,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      items: items ?? this.items,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class PurchaseCreationController
    extends Notifier<PurchaseCreationState> {
  @override
  PurchaseCreationState build() {
    return PurchaseCreationState(
      supplierId: null,
      purchasedAt: DateTime.now(),
      items: const [],
    );
  }

  void setSupplier(int? supplierId) {
    state = state.copyWith(
      supplierId: supplierId,
      clearSupplier: supplierId == null,
    );
  }

  void setPurchasedAt(DateTime date) {
    state = state.copyWith(
      purchasedAt: date,
    );
  }

  void addIngredient(int ingredientId) {
    final alreadyAdded = state.items.any(
      (item) => item.ingredientId == ingredientId,
    );

    if (alreadyAdded) {
      return;
    }

    state = state.copyWith(
      items: [
        ...state.items,
        PurchaseDraftItem(
          ingredientId: ingredientId,
        ),
      ],
    );
  }

  void removeIngredient(int ingredientId) {
    state = state.copyWith(
      items: state.items
          .where((item) => item.ingredientId != ingredientId)
          .toList(),
    );
  }

  void updateQuantity(
    int ingredientId,
    double quantity,
  ) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.ingredientId != ingredientId) {
          return item;
        }

        return item.copyWith(
          quantity: quantity,
        );
      }).toList(),
    );
  }

  void updateUnitCost(
    int ingredientId,
    double unitCost,
  ) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.ingredientId != ingredientId) {
          return item;
        }

        return item.copyWith(
          unitCost: unitCost,
        );
      }).toList(),
    );
  }

  Future<Purchase> save() async {
    final supplierId = state.supplierId;

    if (supplierId == null) {
      throw StateError('Please select a supplier.');
    }

    if (state.items.isEmpty) {
      throw StateError('Please add at least one ingredient.');
    }

    for (final item in state.items) {
      if (item.quantity <= 0) {
        throw StateError(
          'Each ingredient quantity must be greater than zero.',
        );
      }

      if (item.unitCost < 0) {
        throw StateError(
          'Ingredient unit cost cannot be negative.',
        );
      }
    }

    state = state.copyWith(isSaving: true);

    try {
      final branchId = ref.read(currentBranchProvider)?.id;

      final purchase = await ref
          .read(purchaseRepositoryProvider)
          .createPurchase(
            branchId: branchId,
            supplierId: supplierId,
            purchasedAt: state.purchasedAt,
            items: state.items
                .map((item) => item.toCreateItem())
                .toList(),
          );

      state = state.copyWith(isSaving: false);

      return purchase;
    } catch (error) {
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }
}

final purchaseCreationControllerProvider = NotifierProvider<
    PurchaseCreationController,
    PurchaseCreationState>(
  PurchaseCreationController.new,
);