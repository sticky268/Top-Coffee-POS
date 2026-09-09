import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/dashboard_models.dart';

abstract class DashboardRepository {
  Future<DashboardStats> getStats();
  Future<List<RecentOrder>> getRecentOrders({int limit = 5});
  Future<List<SalesDataPoint>> getSalesOverview({int days = 7});
}

class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository(
    this._apiClient, {
    required this.branchId,
  });

  final ApiClient _apiClient;
  final int? branchId;

  Map<String, dynamic>? _cachedData;

  Future<Map<String, dynamic>> _getDashboardData() async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/dashboard',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'];

    if (data is! Map) {
      throw const FormatException('Invalid dashboard response');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> _getData() async {
    if (_cachedData != null) {
      final data = _cachedData!;
      _cachedData = null;
      return data;
    }

    return _getDashboardData();
  }

  @override
  Future<DashboardStats> getStats() async {
    final data = await _getDashboardData();
    _cachedData = data;

    final stats = data['stats'];

    if (stats is! Map) {
      throw const FormatException('Invalid dashboard stats response');
    }

    return DashboardStats(
      todaysSales: _toDouble(stats['todays_sales']),
      todaysOrders: _toInt(stats['todays_orders']),
      averageOrderValue: _toDouble(stats['average_order_value']),
      lowStockItemCount: _toInt(stats['low_stock_item_count']),
    );
  }

  @override
  Future<List<RecentOrder>> getRecentOrders({int limit = 5}) async {
    final data = await _getData();
    final orders = data['recent_orders'];

    if (orders is! List) {
      throw const FormatException('Invalid recent orders response');
    }

    return orders
        .take(limit)
        .map(
          (json) => RecentOrder(
            orderNumber: '#${json['order_number']}',
            time: DateTime.parse(json['created_at'] as String).toLocal(),
            customerOrTable: _customerOrTable(json['order_type']),
            itemCount: _toInt(json['item_count']),
            total: _toDouble(json['total']),
            status: _orderStatus(json['status']),
          ),
        )
        .toList();
  }

  @override
  Future<List<SalesDataPoint>> getSalesOverview({int days = 7}) async {
    final data = await _getData();
    final sales = data['sales_overview'];

    if (sales is! List) {
      throw const FormatException('Invalid sales overview response');
    }

    return sales
        .take(days)
        .map(
          (json) => SalesDataPoint(
            date: DateTime.parse(json['date'] as String),
            total: _toDouble(json['total']),
          ),
        )
        .toList();
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _customerOrTable(dynamic orderType) {
    switch (orderType?.toString()) {
      case 'takeaway':
        return 'Takeaway';
      case 'dine_in':
        return 'Dine-in';
      case 'delivery':
        return 'Delivery';
      default:
        return null;
    }
  }

  static OrderStatus _orderStatus(dynamic status) {
    switch (status?.toString()) {
      case 'pending':
        return OrderStatus.pending;
      case 'preparing':
        return OrderStatus.preparing;
      case 'ready':
        return OrderStatus.ready;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'completed':
      default:
        return OrderStatus.completed;
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final currentBranch = ref.watch(currentBranchProvider);

  return ApiDashboardRepository(
    ref.watch(apiClientProvider),
    branchId: currentBranch?.id,
  );
});
