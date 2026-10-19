import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/sales_report.dart';
import '../domain/profit_report.dart';

class SalesReportsRepository {
  SalesReportsRepository(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> _get(Map<String, Object> parameters) async {
    final response = await _api.request(
        (dio) => dio.get('/reports/sales', queryParameters: parameters));
    final data = response.data['data'];
    if (data is! Map) {
      throw const FormatException('Invalid sales report response');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> branchComparison(SalesReportQuery query, int? branchId) =>
      _get({...query.parameters(branchId), 'report': 'branches'});

  Future<ProfitReport> profit(SalesReportQuery query, int? branchId) async =>
      ProfitReport(
          await _get({...query.parameters(branchId), 'report': 'profit'}));

  Future<Map<String, dynamic>> profitDetails(
          SalesReportQuery query, int? branchId,
          {int? productId, String? category, int page = 1}) =>
      _get({
        ...query.parameters(branchId),
        'report': 'profit',
        'detail': 'profit',
        'page': page,
        if (productId != null) 'product_id': productId,
        if (category != null) 'profit_category': category
      });

  Future<Map<String, dynamic>> inventory(SalesReportQuery query, int? branchId,
          {bool detail = false,
          int? ingredientId,
          String kind = 'ledger',
          int page = 1}) =>
      _get({
        ...query.parameters(branchId),
        'report': 'inventory',
        if (detail) 'detail': 'inventory',
        if (ingredientId != null) 'ingredient_id': ingredientId,
        'inventory_kind': kind,
        'page': page
      });
  Future<SalesReport> load(SalesReportQuery query, int? branchId) async =>
      SalesReport(await _get(query.parameters(branchId)));

  Future<Map<String, dynamic>> activity(SalesReportQuery query, int? branchId,
          {bool detail = false,
          int page = 1,
          int? weekday,
          int? hour,
          int? cashier,
          String kind = 'orders'}) =>
      _get({
        ...query.parameters(branchId),
        'report': 'activity',
        if (detail) 'detail': 'activity',
        'page': page,
        'activity_kind': kind,
        if (weekday != null) 'weekday': weekday,
        if (hour != null) 'hour': hour,
        if (cashier != null) 'source_cashier': cashier
      });

  Future<Map<String, dynamic>> details(SalesReportQuery query, int? branchId,
          {required String kind,
          String? metric,
          String? method,
          int page = 1}) =>
      _get({
        ...query.parameters(branchId),
        'detail': kind,
        'page': page,
        if (metric != null) 'metric': metric,
        if (method != null) 'method': method,
      });
}

final salesReportsRepositoryProvider =
    Provider((ref) => SalesReportsRepository(ref.watch(apiClientProvider)));
