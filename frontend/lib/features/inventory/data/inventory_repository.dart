import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/inventory_models.dart';

/// Data boundary for the Inventory feature.
abstract class InventoryRepository {
  Future<List<InventoryIngredient>> getIngredients({
    int? branchId,
  });

  Future<List<InventoryUnit>> getUnits();

  Future<InventoryIngredient> createIngredient({
    required String name,
    required int unitId,
    double reorderThreshold = 0,
    bool isActive = true,
    int? branchId,
  });

  Future<InventoryIngredient> recordStockMovement({
    required int ingredientId,
    required String type,
    required double quantity,
    String? reason,
  });
}

class ApiInventoryRepository implements InventoryRepository {
  ApiInventoryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<InventoryIngredient>> getIngredients({
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/ingredients',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List;

    return data
        .map(
          (json) => InventoryIngredient.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<List<InventoryUnit>> getUnits() async {
    final response = await _apiClient.request(
      (dio) => dio.get('/units'),
    );

    final data = response.data['data'] as List;

    return data
        .map(
          (json) => InventoryUnit.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<InventoryIngredient> createIngredient({
    required String name,
    required int unitId,
    double reorderThreshold = 0,
    bool isActive = true,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/ingredients',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'name': name,
          'unit_id': unitId,
          'reorder_threshold': reorderThreshold,
          'is_active': isActive,
        },
      ),
    );

    return InventoryIngredient.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<InventoryIngredient> recordStockMovement({
    required int ingredientId,
    required String type,
    required double quantity,
    String? reason,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/ingredients/$ingredientId/movements',
        data: {
          'type': type,
          'quantity': quantity,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      ),
    );

    final data = response.data['data'] as Map<String, dynamic>;

    return InventoryIngredient.fromJson(
      data['ingredient'] as Map<String, dynamic>,
    );
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return ApiInventoryRepository(ref.watch(apiClientProvider));
});



