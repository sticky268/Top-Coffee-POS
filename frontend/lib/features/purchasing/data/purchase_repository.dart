import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/purchase_models.dart';

/// Data boundary for Purchasing API operations.
abstract class PurchaseRepository {
  Future<PurchaseHistoryPage> getPurchaseHistory({
    int? branchId,
    int page = 1,
    int perPage = 15,
  });

  Future<Purchase> createPurchase({
    int? branchId,
    required int supplierId,
    required DateTime purchasedAt,
    required List<PurchaseCreateItem> items,
  });
}

class PurchaseCreateItem {
  const PurchaseCreateItem({
    required this.ingredientId,
    required this.quantity,
    required this.unitCost,
  });

  final int ingredientId;
  final double quantity;
  final double unitCost;

  Map<String, dynamic> toJson() {
    return {
      'ingredient_id': ingredientId,
      'quantity': quantity,
      'unit_cost': unitCost,
    };
  }
}

class ApiPurchaseRepository implements PurchaseRepository {
  ApiPurchaseRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PurchaseHistoryPage> getPurchaseHistory({
    int? branchId,
    int page = 1,
    int perPage = 15,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/purchases',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return PurchaseHistoryPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  @override
  Future<Purchase> createPurchase({
    int? branchId,
    required int supplierId,
    required DateTime purchasedAt,
    required List<PurchaseCreateItem> items,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/purchases',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'supplier_id': supplierId,
          'purchased_at': purchasedAt.toIso8601String().split('T').first,
          'items': items.map((item) => item.toJson()).toList(),
        },
      ),
    );

    return Purchase.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return ApiPurchaseRepository(
    ref.watch(apiClientProvider),
  );
});