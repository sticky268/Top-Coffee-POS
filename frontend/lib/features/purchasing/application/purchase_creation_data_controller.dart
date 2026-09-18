import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory_models.dart';
import '../data/supplier_repository.dart';
import '../domain/purchase_models.dart';

class PurchaseCreationData {
  const PurchaseCreationData({
    required this.suppliers,
    required this.ingredients,
  });

  final List<PurchaseSupplier> suppliers;
  final List<InventoryIngredient> ingredients;
}

class PurchaseCreationDataController
    extends AsyncNotifier<PurchaseCreationData> {
  @override
  Future<PurchaseCreationData> build() async {
    final branchId = ref.watch(currentBranchProvider)?.id;

    final supplierRepository =
        ref.read(purchaseSupplierRepositoryProvider);
    final inventoryRepository =
        ref.read(inventoryRepositoryProvider);

    final results = await Future.wait([
      supplierRepository.getSuppliers(
        branchId: branchId,
      ),
      inventoryRepository.getIngredients(
        branchId: branchId,
      ),
    ]);

    return PurchaseCreationData(
      suppliers: results[0] as List<PurchaseSupplier>,
      ingredients: results[1] as List<InventoryIngredient>,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final branchId = ref.read(currentBranchProvider)?.id;

      final supplierRepository =
          ref.read(purchaseSupplierRepositoryProvider);
      final inventoryRepository =
          ref.read(inventoryRepositoryProvider);

      final results = await Future.wait([
        supplierRepository.getSuppliers(
          branchId: branchId,
        ),
        inventoryRepository.getIngredients(
          branchId: branchId,
        ),
      ]);

      return PurchaseCreationData(
        suppliers: results[0] as List<PurchaseSupplier>,
        ingredients: results[1] as List<InventoryIngredient>,
      );
    });
  }
}

final purchaseCreationDataControllerProvider =
    AsyncNotifierProvider<
        PurchaseCreationDataController,
        PurchaseCreationData>(
  PurchaseCreationDataController.new,
);