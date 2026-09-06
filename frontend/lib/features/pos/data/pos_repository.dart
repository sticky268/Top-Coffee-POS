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
  Future<List<PosCategory>> getCategories();
  Future<List<PosProduct>> getProducts();

  /// Submits the cart as a real order via POST /api/v1/orders. Only sends
  /// product/variant IDs and quantities — never client-side prices, since
  /// the backend recomputes every line server-side (see
  /// OrderController::store()'s docblock for why).
  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    required String paymentMethod,
    double? tendered,
    double discountTotal = 0,
  });
}

class ApiPosRepository implements PosRepository {
  ApiPosRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PosCategory>> getCategories() async {
    final response = await _apiClient.request((dio) => dio.get('/categories'));
    final data = response.data['data'] as List;
    return data.map((json) => PosCategory.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<PosProduct>> getProducts() async {
    // Fetched once, unfiltered — category selection filters this list
    // locally (see PosCatalogController.selectCategory), rather than
    // issuing a new request per category tap. The backend does support a
    // ?category_id= param (see ProductController), but this endpoint
    // deliberately doesn't use it, per the task's explicit instruction.
    final response = await _apiClient.request((dio) => dio.get('/products'));
    final data = response.data['data'] as List;
    return data.map((json) => PosProduct.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    required String paymentMethod,
    double? tendered,
    double discountTotal = 0,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post('/orders', data: {
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
