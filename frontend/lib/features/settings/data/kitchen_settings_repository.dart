import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;

class KitchenSettingsRepository {
  KitchenSettingsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<bool> load({required int branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/branches/$branchId/kitchen-settings'),
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return data['use_kitchen_display'] as bool? ?? true;
  }

  Future<bool> update({
    required int branchId,
    required bool useKitchenDisplay,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/branches/$branchId/kitchen-settings',
        data: {'use_kitchen_display': useKitchenDisplay},
      ),
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return data['use_kitchen_display'] as bool? ?? useKitchenDisplay;
  }
}

final kitchenSettingsRepositoryProvider = Provider<KitchenSettingsRepository>((ref) {
  return KitchenSettingsRepository(ref.watch(apiClientProvider));
});
