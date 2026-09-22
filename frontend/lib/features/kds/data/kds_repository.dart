import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../domain/kds_models.dart';

abstract class KdsRepository {
  Future<List<KitchenTicket>> getTickets({
    int? branchId,
  });

  Future<KitchenTicket> updateTicketStatus({
    required int ticketId,
    required String status,
  });
}

class ApiKdsRepository implements KdsRepository {
  ApiKdsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<KitchenTicket>> getTickets({
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/kitchen/tickets',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'] as List? ?? const [];

    return data
        .map(
          (json) => KitchenTicket.fromJson(
            json as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<KitchenTicket> updateTicketStatus({
    required int ticketId,
    required String status,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/kitchen/tickets/$ticketId/status',
        data: {
          'status': status,
        },
      ),
    );

    return KitchenTicket.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}

final kdsRepositoryProvider = Provider<KdsRepository>((ref) {
  return ApiKdsRepository(ref.watch(apiClientProvider));
});
