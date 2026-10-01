import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/subscription_models.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(apiClientProvider));
});

class SubscriptionRepository {
  SubscriptionRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<SubscriptionDetails> getSubscription() async {
    final response = await _apiClient.request(
      (dio) => dio.get('/subscription'),
    );

    return SubscriptionDetails.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}
