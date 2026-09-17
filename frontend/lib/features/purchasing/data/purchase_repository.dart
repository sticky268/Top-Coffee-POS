import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/purchase_models.dart';

/// Data boundary for the Purchasing feature.
abstract class PurchaseRepository {
  Future<PurchaseHistoryPage> getPurchaseHistory({
    int? branchId,
    int page = 1,
    int perPage = 15,
  });
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
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return ApiPurchaseRepository(ref.watch(apiClientProvider));
});