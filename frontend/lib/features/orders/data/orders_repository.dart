import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/order_models.dart';
import '../domain/orders_list_filters.dart';

/// Data boundary for order history.
abstract class OrdersRepository {
  Future<OrderListPage> getOrders({
    int page = 1,
    int? branchId,
    OrdersListFilters filters = OrdersListFilters.empty,
  });

  Future<OrderDetail> getOrder(int id);
}

class ApiOrdersRepository implements OrdersRepository {
  ApiOrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<OrderListPage> getOrders({
    int page = 1,
    int? branchId,
    OrdersListFilters filters = OrdersListFilters.empty,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/orders',
        queryParameters: {
          'page': page,
          if (branchId != null) 'branch_id': branchId,
          if (filters.orderNumber?.trim().isNotEmpty ?? false)
            'order_number': filters.orderNumber!.trim(),
          if (filters.status != null) 'status': filters.status,
          if (filters.paymentMethod != null)
            'payment_method': filters.paymentMethod,
          if (filters.dateFrom != null)
            'date_from': _formatDate(filters.dateFrom!),
          if (filters.dateTo != null)
            'date_to': _formatDate(filters.dateTo!),
        },
      ),
    );

    final data = response.data['data'] as List;
    final meta = response.data['meta'] as Map<String, dynamic>;

    return OrderListPage(
      orders: data
          .map(
            (json) =>
                OrderSummary.fromJson(json as Map<String, dynamic>),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  @override
  Future<OrderDetail> getOrder(int id) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/orders/$id'),
    );

    return OrderDetail.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return ApiOrdersRepository(ref.watch(apiClientProvider));
});
