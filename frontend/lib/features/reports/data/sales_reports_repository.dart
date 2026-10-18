import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/sales_report.dart';

class SalesReportsRepository {
  SalesReportsRepository(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> _get(Map<String, Object> parameters) async {
    final response = await _api.request(
        (dio) => dio.get('/reports/sales', queryParameters: parameters));
    final data = response.data['data'];
    if (data is! Map)
      throw const FormatException('Invalid sales report response');
    return Map<String, dynamic>.from(data);
  }

  Future<SalesReport> load(SalesReportQuery query, int? branchId) async =>
      SalesReport(await _get(query.parameters(branchId)));

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
