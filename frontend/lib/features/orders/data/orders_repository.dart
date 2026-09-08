import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/order_models.dart';

/// Data boundary for order history. Mirrors PosRepository exactly: real
/// backend already exists and is verified (GET /api/v1/orders,
/// GET /api/v1/orders/{id}), calls it via the existing [ApiClient] — no
/// second HTTP client, no mock implementation needed here.
abstract class OrdersRepository {
  /// [branchId]: forwarded as the `branch_id` query param — the backend
  /// endpoint accepts it (OrderController::index()), narrowing the list to
  /// a single branch on top of the BranchScoped trait's own restriction
  /// to branches the user has access to at all. Needed for the branch
  /// switcher: without it, a multi-branch user always sees every branch
  /// they can access at once, with no way to narrow to just one.
  Future<OrderListPage> getOrders({int page = 1, int? branchId});
  Future<OrderDetail> getOrder(int id);
}

class ApiOrdersRepository implements OrdersRepository {
  ApiOrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<OrderListPage> getOrders({int page = 1, int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/orders', queryParameters: {
        'page': page,
        if (branchId != null) 'branch_id': branchId,
      }),
    );

    final data = response.data['data'] as List;
    final meta = response.data['meta'] as Map<String, dynamic>;

    return OrderListPage(
      orders: data.map((json) => OrderSummary.fromJson(json as Map<String, dynamic>)).toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  @override
  Future<OrderDetail> getOrder(int id) async {
    final response = await _apiClient.request((dio) => dio.get('/orders/$id'));
    return OrderDetail.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

// Reuses the existing apiClientProvider from features/auth/data — same
// pattern already established by PosRepository, deliberately not
// redeclared here.
final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return ApiOrdersRepository(ref.watch(apiClientProvider));
});
