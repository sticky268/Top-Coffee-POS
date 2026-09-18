import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/purchase_models.dart';

/// Data boundary for supplier data used by Purchasing.
abstract class PurchaseSupplierRepository {
  Future<List<PurchaseSupplier>> getSuppliers({
    int? branchId,
  });
}

class ApiPurchaseSupplierRepository
    implements PurchaseSupplierRepository {
  ApiPurchaseSupplierRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PurchaseSupplier>> getSuppliers({
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/suppliers',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List;

    return data
        .map(
          (json) => PurchaseSupplier.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}

final purchaseSupplierRepositoryProvider =
    Provider<PurchaseSupplierRepository>((ref) {
  return ApiPurchaseSupplierRepository(
    ref.watch(apiClientProvider),
  );
});