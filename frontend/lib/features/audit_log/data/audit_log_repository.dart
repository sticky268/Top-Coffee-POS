import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/audit_log_models.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(ref.watch(apiClientProvider));
});

class AuditLogRepository {
  AuditLogRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AuditLogListPage> getAuditLogs({
    String? search,
    String? action,
    int? userId,
    String? auditableType,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/audit-logs',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (action != null && action.isNotEmpty) 'action': action,
          if (userId != null) 'user_id': userId,
          if (auditableType != null && auditableType.isNotEmpty)
            'auditable_type': auditableType,
          if (from != null) 'from': _formatDate(from),
          if (to != null) 'to': _formatDate(to, endOfDay: true),
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return AuditLogListPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  String _formatDate(
    DateTime value, {
    bool endOfDay = false,
  }) {
    final date = DateTime(
      value.year,
      value.month,
      value.day,
      endOfDay ? 23 : 0,
      endOfDay ? 59 : 0,
      endOfDay ? 59 : 0,
    );

    return date.toIso8601String();
  }
}