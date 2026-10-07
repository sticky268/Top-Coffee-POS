import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/pos_models.dart';

/// Data boundary for the POS feature.
abstract class PosRepository {
  Future<List<PosCategory>> getCategories({int? branchId});
  Future<List<PosProduct>> getProducts({int? branchId});
  Future<List<PosTable>> getTables({int? branchId});

  Future<PosTable> createTable({
    required String name,
    required int capacity,
    String status = 'available',
    String? section,
    String shape = 'square',
    String? color,
    bool isActive = true,
    int? branchId,
  });

  Future<PosTable> updateTable({
    required int tableId,
    String? name,
    int? capacity,
    String? status,
    String? section,
    String? shape,
    String? color,
    bool? isActive,
    int? branchId,
  });

  Future<void> deleteTable({
    required int tableId,
    int? branchId,
  });

  Future<OrderConfirmation> holdOrder({
    required List<CartItem> items,
    String? requestUuid,
    required String orderType,
    required int tableId,
    double discountTotal = 0,
    int? customerId,
    int? branchId,
  });

  Future<OrderConfirmation> updateHeldOrder({
    required int orderId,
    required List<Map<String, dynamic>> items,
    double discountTotal = 0,
    int? branchId,
    String? voidReason,
  });

  Future<void> cancelHeldOrder({required int orderId});

  Future<OrderConfirmation> payHeldOrder({
    required int orderId,
    required String paymentMethod,
    double? expectedTotal,
    double? tendered,
    List<Map<String, dynamic>>? splitPayments,
    int? branchId,
  });

  Future<OrderReceipt> getOrderReceipt({
    required int orderId,
  });

  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    String? requestUuid,
    required String paymentMethod,
    required String orderType,
    int? tableId,
    double? tendered,
    List<Map<String, dynamic>>? splitPayments,
    double discountTotal = 0,
    int? branchId,
    int? customerId,
  });
}

class ApiPosRepository implements PosRepository {
  ApiPosRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PosCategory>> getCategories({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/categories',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List;
    return data
        .map((json) => PosCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PosProduct>> getProducts({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/products',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List;
    return data
        .map((json) => PosProduct.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PosTable>> getTables({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/tables',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List;
    return data
        .map((json) => PosTable.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PosTable> createTable({
    required String name,
    required int capacity,
    String status = 'available',
    String? section,
    String shape = 'square',
    String? color,
    bool isActive = true,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/tables',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'name': name,
          'capacity': capacity,
          'status': status,
          'section': section,
          'shape': shape,
          'color': color,
          'is_active': isActive,
        },
      ),
    );

    return PosTable.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<PosTable> updateTable({
    required int tableId,
    String? name,
    int? capacity,
    String? status,
    String? section,
    String? shape,
    String? color,
    bool? isActive,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/tables/$tableId',
        data: {
          if (branchId != null) 'branch_id': branchId,
          if (name != null) 'name': name,
          if (capacity != null) 'capacity': capacity,
          if (status != null) 'status': status,
          if (section != null) 'section': section,
          if (shape != null) 'shape': shape,
          if (color != null) 'color': color,
          if (isActive != null) 'is_active': isActive,
        },
      ),
    );

    return PosTable.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteTable({
    required int tableId,
    int? branchId,
  }) async {
    await _apiClient.request(
      (dio) => dio.delete(
        '/tables/$tableId',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );
  }

  @override
  Future<OrderConfirmation> holdOrder({
    required List<CartItem> items,
    String? requestUuid,
    required String orderType,
    required int tableId,
    double discountTotal = 0,
    int? customerId,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/orders/hold',
        data: {
          if (requestUuid != null) 'uuid': requestUuid,
          if (branchId != null) 'branch_id': branchId,
          if (customerId != null) 'customer_id': customerId,
          'order_type': orderType,
          'table_id': tableId,
          'items': items
              .map(
                (item) => {
                  'product_id': item.product.id,
                  'product_variant_id': item.variant?.id,
                  'quantity': item.quantity,
                },
              )
              .toList(),
          'discount_total': discountTotal,
        },
      ),
    );

    return OrderConfirmation.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<OrderConfirmation> updateHeldOrder({
    required int orderId,
    required List<Map<String, dynamic>> items,
    double discountTotal = 0,
    int? customerId,
    int? branchId,
    String? voidReason,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/orders/$orderId/hold',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'items': items,
          'discount_total': discountTotal,
          if (voidReason != null && voidReason.trim().isNotEmpty)
            'void_reason': voidReason.trim(),
        },
      ),
    );

    return OrderConfirmation.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> cancelHeldOrder({required int orderId}) async {
    await _apiClient.request((dio) => dio.post('/orders/$orderId/cancel'));
  }

  @override
  Future<OrderConfirmation> payHeldOrder({
    required int orderId,
    required String paymentMethod,
    double? expectedTotal,
    double? tendered,
    List<Map<String, dynamic>>? splitPayments,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/orders/$orderId/pay',
        data: {
          if (branchId != null) 'branch_id': branchId,
          if (expectedTotal != null) 'expected_total': expectedTotal,
          'payment': {
            'method': paymentMethod,
            if (tendered != null) 'tendered': tendered,
            if (paymentMethod == 'split' && splitPayments != null)
              'payments': splitPayments,
          },
        },
      ),
    );

    return OrderConfirmation.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }



  @override
  Future<OrderReceipt> getOrderReceipt({
    required int orderId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/orders/$orderId'),
    );

    return OrderReceipt.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<OrderConfirmation> createOrder({
    required List<CartItem> items,
    String? requestUuid,
    required String paymentMethod,
    required String orderType,
    int? tableId,
    double? tendered,
    List<Map<String, dynamic>>? splitPayments,
    double discountTotal = 0,
    int? customerId,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/orders',
        data: {
          if (requestUuid != null) 'uuid': requestUuid,
          if (branchId != null) 'branch_id': branchId,
          if (customerId != null) 'customer_id': customerId,
          'order_type': orderType,
          if (tableId != null) 'table_id': tableId,
          'items': items
              .map(
                (item) => {
                  'product_id': item.product.id,
                  'product_variant_id': item.variant?.id,
                  'quantity': item.quantity,
                },
              )
              .toList(),
          'discount_total': discountTotal,
          'payment': {
            'method': paymentMethod,
            if (tendered != null) 'tendered': tendered,
            if (paymentMethod == 'split' && splitPayments != null)
              'payments': splitPayments,
          },
        },
      ),
    );

    return OrderConfirmation.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return ApiPosRepository(ref.watch(apiClientProvider));
});
