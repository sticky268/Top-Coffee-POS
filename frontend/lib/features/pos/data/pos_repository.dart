import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/offline/local_store.dart';
import '../../../core/offline/order_outbox.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
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
  ApiPosRepository(this._apiClient,
      {LocalStore? localStore,
      OrderOutbox? outbox,
      int? Function()? userId,
      void Function()? onCachedCatalog})
      : _localStore = localStore,
        _outbox = outbox,
        _userId = userId,
        _onCachedCatalog = onCachedCatalog;

  final ApiClient _apiClient;
  final LocalStore? _localStore;
  final OrderOutbox? _outbox;
  final int? Function()? _userId;
  final void Function()? _onCachedCatalog;

  Future<List<dynamic>> _catalog(String path, int? branchId) async {
    final userId = _userId?.call();
    final cacheKey = userId == null || branchId == null
        ? null
        : 'catalog:$userId:$branchId:$path';
    try {
      final response = await _apiClient.request((dio) => dio.get(path,
          queryParameters: {if (branchId != null) 'branch_id': branchId}));
      final data = response.data['data'] as List;
      if (cacheKey != null && _localStore != null) {
        try {
          await _localStore.write(
              cacheKey,
              jsonEncode({
                'saved_at': DateTime.now().toUtc().toIso8601String(),
                'data': data,
              }));
        } catch (_) {
          // An unavailable cache must not turn a successful read into a failure.
        }
      }
      return data;
    } on NetworkException {
      if (cacheKey != null && _localStore != null) {
        final stored = await _localStore.read(cacheKey);
        if (stored != null) {
          final snapshot = jsonDecode(stored) as Map<String, dynamic>;
          final age = DateTime.now()
              .toUtc()
              .difference(DateTime.parse(snapshot['saved_at'] as String));
          if (!age.isNegative && age < const Duration(hours: 24)) {
            _onCachedCatalog?.call();
            return snapshot['data'] as List;
          }
        }
      }
      rethrow;
    }
  }

  Future<OrderConfirmation> _submit(
      String endpoint, Map<String, dynamic> payload) async {
    final userId = _userId?.call();
    final branchId = payload['branch_id'] as int?;
    PendingOrder? pending;
    if (_outbox != null) {
      if (userId == null || branchId == null) {
        throw const AuthException(
            'Sign in and select a branch before submitting an order.');
      }
      pending = await _outbox.prepare(
          userId: userId,
          branchId: branchId,
          endpoint: endpoint,
          payload: payload);
      payload = pending.payload;
    }
    Future<OrderConfirmation> send() async {
      try {
        final response = await _apiClient
            .request((dio) => dio.post(endpoint, data: payload));
        final confirmation = OrderConfirmation.fromJson(
            response.data['data'] as Map<String, dynamic>);
        if (pending != null) {
          await _outbox!.finish(pending, orderId: confirmation.orderId);
        }
        return confirmation;
      } catch (error) {
        if (pending != null) {
          await _outbox!.finish(pending, error: error);
          if (error is NetworkException || error is ServerException) {
            throw QueuedOrderException(pending.uuid);
          }
        }
        rethrow;
      }
    }

    return pending == null
        ? send()
        : _outbox!.withRequestLock(pending.uuid, send);
  }

  @override
  Future<List<PosCategory>> getCategories({int? branchId}) async {
    final data = await _catalog('/categories', branchId);
    return data
        .map((json) => PosCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PosProduct>> getProducts({int? branchId}) async {
    final data = await _catalog('/products', branchId);
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
    return _submit('/orders/hold', {
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
    });
  }

  @override
  Future<OrderConfirmation> updateHeldOrder({
    required int orderId,
    required List<Map<String, dynamic>> items,
    double discountTotal = 0,
    int? customerId,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/orders/$orderId/hold',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'items': items,
          'discount_total': discountTotal,
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
    return _submit('/orders', {
      if (_outbox != null)
        'expected_total': double.parse(
            (items.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                    discountTotal)
                .clamp(0, double.infinity)
                .toStringAsFixed(2)),
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
    });
  }
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return ApiPosRepository(
    ref.watch(apiClientProvider),
    localStore: ref.watch(localStoreProvider),
    outbox: ref.watch(orderOutboxProvider),
    userId: () {
      final auth = ref.read(authControllerProvider);
      return auth is AuthAuthenticated ? auth.user.id : null;
    },
    onCachedCatalog: () =>
        ref.read(cachedCatalogProvider.notifier).state = true,
  );
});

final cachedCatalogProvider = StateProvider<bool>((ref) => false);
