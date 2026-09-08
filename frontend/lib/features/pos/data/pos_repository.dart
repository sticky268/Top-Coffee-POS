import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/pos_models.dart';

/// Data boundary for the POS catalog. Unlike DashboardRepository (which
/// still has no backend and uses a local/mock data source), the backend
/// for this feature already exists and is verified
/// (GET /api/v1/categories, GET /api/v1/products) — so there is only one
/// implementation here, calling the real API via the existing [ApiClient].
abstract class PosRepository {
  /// [branchId]: forwarded as the `branch_id` query param. When omitted,
  /// the backend falls back to the authenticated user's primary branch
  /// (see CategoryController/ProductController) — passing it explicitly
  /// is what lets the app's branch switcher actually change which
  /// branch's catalog is shown, rather than always defaulting silently.
  Future<List<PosCategory>> getCategories({int? branchId});
  Future<List<PosProduct>> getProducts({int? branchId});

  /// Submits the cart as a real order via POST /api/v1/orders. Only sends
  /// product/variant IDs and quantities — never client-side prices, since
  /// the backend recomputes every line server-side (see
  /// OrderController::store()'s docblock for why).
  ///
  /// [branchId]: forwarded as `branch_id` in the request body — without
  /// it, the backend falls back to the user's primary branch, which would
  /// silently ignore the currently-selected branch for order creation.
  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    required String paymentMethod,
    double? tendered,
    double discountTotal = 0,
    int? branchId,
  });
}

class ApiPosRepository implements PosRepository {
  ApiPosRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PosCategory>> getCategories({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/categories', queryParameters: {
        if (branchId != null) 'branch_id': branchId,
      }),
    );
    final data = response.data['data'] as List;
    return data.map((json) => PosCategory.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<PosProduct>> getProducts({int? branchId}) async {
    // Fetched once (per branch), unfiltered by category — category
    // selection filters this list locally (see
    // PosCatalogController.selectCategory), rather than issuing a new
    // request per category tap. The backend does support a
    // ?category_id= param too (see ProductController), but this endpoint
    // deliberately doesn't use it, per that task's explicit instruction —
    // branch_id is a separate, orthogonal concern from that decision.
    final response = await _apiClient.request(
      (dio) => dio.get('/products', queryParameters: {
        if (branchId != null) 'branch_id': branchId,
      }),
    );
    final data = response.data['data'] as List;
    return data.map((json) => PosProduct.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    required String paymentMethod,
    double? tendered,
    double discountTotal = 0,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post('/orders', data: {
        if (branchId != null) 'branch_id': branchId,
        // No dine-in/table-selection UI exists yet — every order created
        // from this screen is a takeaway, matching what's actually
        // buildable right now rather than guessing at a dine-in flow.
        'order_type': 'takeaway',
        'items': items
            .map((item) => {
                  'product_id': item.product.id,
                  'product_variant_id': item.variant?.id,
                  'quantity': item.quantity,
                })
            .toList(),
        'discount_total': discountTotal,
        'payment': {
          'method': paymentMethod,
          if (tendered != null) 'tendered': tendered,
        },
      }),
    );
    return OrderConfirmation.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

// Reuses the existing apiClientProvider from features/auth/data —
// deliberately not redeclared here, per "Do not create a second HTTP
// client" / do not create a second provider for the same ApiClient.
final posRepositoryProvider = Provider<PosRepository>((ref) {
  return ApiPosRepository(ref.watch(apiClientProvider));
});
