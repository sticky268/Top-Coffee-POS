import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/purchase_models.dart';

/// Data boundary for supplier data used by Purchasing.
abstract class PurchaseSupplierRepository {
  Future<List<PurchaseSupplier>> getSuppliers({
    int? branchId,
  });

  Future<PurchaseSupplier> createSupplier({
    int? branchId,
    required String name,
    String? contactName,
    String? phone,
    String? email,
  });

  Future<PurchaseSupplier> updateSupplier({
    required int id,
    int? branchId,
    required String name,
    String? contactName,
    String? phone,
    String? email,
  });

  Future<void> deleteSupplier(int id);
}

class ApiPurchaseSupplierRepository
    implements PurchaseSupplierRepository {
  ApiPurchaseSupplierRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PurchaseSupplier> createSupplier({
    int? branchId,
    required String name,
    String? contactName,
    String? phone,
    String? email,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/suppliers',
        data: {
          'branch_id': branchId,
          'name': name,
          'contact_name': contactName,
          'phone': phone,
          'email': email,
        },
      ),
    );

    return PurchaseSupplier.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<PurchaseSupplier> updateSupplier({
    required int id,
    int? branchId,
    required String name,
    String? contactName,
    String? phone,
    String? email,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/suppliers/$id',
        data: {
          'branch_id': branchId,
          'name': name,
          'contact_name': contactName,
          'phone': phone,
          'email': email,
        },
      ),
    );

    return PurchaseSupplier.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteSupplier(int id) async {
    await _apiClient.request(
      (dio) => dio.delete('/suppliers/$id'),
    );
  }
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