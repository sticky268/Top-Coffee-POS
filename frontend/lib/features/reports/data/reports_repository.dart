import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/reports_models.dart';

abstract class ReportsRepository {
  Future<ReportsData> getReport({
    required String dateFrom,
    required String dateTo,
  });
}

class ApiReportsRepository implements ReportsRepository {
  ApiReportsRepository(
    this._apiClient, {
    required this.branchId,
  });

  final ApiClient _apiClient;
  final int? branchId;

  @override
  Future<ReportsData> getReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/reports',
        queryParameters: {
          'date_from': dateFrom,
          'date_to': dateTo,
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'];

    if (data is! Map) {
      throw const FormatException('Invalid reports response');
    }

    return ReportsData.fromJson(
      Map<String, dynamic>.from(data),
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final currentBranch = ref.watch(currentBranchProvider);

  return ApiReportsRepository(
    ref.watch(apiClientProvider),
    branchId: currentBranch?.id,
  );
});
