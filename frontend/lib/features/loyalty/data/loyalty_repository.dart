import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/loyalty_models.dart';

final loyaltyRepositoryProvider = Provider<LoyaltyRepository>((ref) {
  return LoyaltyRepository(ref.watch(apiClientProvider));
});

class LoyaltyRepository {
  LoyaltyRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<CustomerLoyalty> getCustomerLoyalty({
    required int customerId,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/customers/$customerId/loyalty',
        queryParameters: {
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return CustomerLoyalty.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<LoyaltyTransaction> adjustCustomerLoyalty({
    required int customerId,
    required int points,
    String? description,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/customers/$customerId/loyalty/adjust',
        data: {
          'points': points,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    final data = response.data['data'];
    final transaction = data is Map<String, dynamic>
        ? data['transaction']
        : null;

    if (transaction is Map<String, dynamic>) {
      return LoyaltyTransaction.fromJson(transaction);
    }

    throw StateError(
      'Unexpected loyalty adjustment response.',
    );
  }

  Future<LoyaltySettings> getSettings({
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/loyalty/settings',
        queryParameters: {
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    return LoyaltySettings.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<LoyaltySettings> updateSettings({
    required bool isEnabled,
    required double pointsPerCurrencyUnit,
    required double pointsPerRewardCurrencyUnit,
    required int minimumRedeemPoints,
    required bool redemptionEnabled,
    int? expirationMonths,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/loyalty/settings',
        data: {
          'is_enabled': isEnabled,
          'points_per_currency_unit': pointsPerCurrencyUnit,
          'points_per_reward_currency_unit':
              pointsPerRewardCurrencyUnit,
          'minimum_redeem_points': minimumRedeemPoints,
          'redemption_enabled': redemptionEnabled,
          'expiration_months': expirationMonths,
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    return LoyaltySettings.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
}