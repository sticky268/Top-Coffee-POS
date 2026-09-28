import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/loyalty/data/loyalty_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late LoyaltyRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = LoyaltyRepository(apiClient);
  });

  test('getCustomerLoyalty parses the customer loyalty response', () async {
    final responseData = {
      'success': true,
      'data': {
        'customer': {
          'id': 5,
          'branch_id': 1,
          'name': 'John Doe',
          'phone': '012345678',
          'email': null,
          'notes': null,
          'completed_orders_count': 3,
          'completed_orders_total': 25.50,
        },
        'account': {
          'id': 10,
          'customer_id': 5,
          'points_balance': 250,
          'lifetime_earned': 400,
          'lifetime_redeemed': 150,
          'created_at': null,
          'updated_at': null,
        },
        'transactions': [
          {
            'id': 20,
            'customer_loyalty_account_id': 10,
            'customer_id': 5,
            'branch_id': 1,
            'order_id': 12,
            'type': 'earned',
            'points': 100,
            'balance_after': 250,
            'description': 'Points earned from completed order',
            'branch': {'id': 1, 'name': 'Main Branch'},
            'order': {'id': 12, 'uuid': 'order-uuid-12'},
            'created_at': null,
            'updated_at': null,
          },
        ],
        'meta': {
          'current_page': 1,
          'last_page': 1,
          'per_page': 20,
          'total': 1,
        },
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/customers/5/loyalty'),
      ),
    );

    final loyalty = await repository.getCustomerLoyalty(
      customerId: 5,
    );

    expect(loyalty.customer.id, 5);
    expect(loyalty.account.pointsBalance, 250);
    expect(loyalty.account.lifetimeEarned, 400);
    expect(loyalty.account.lifetimeRedeemed, 150);
    expect(loyalty.transactions, hasLength(1));
    expect(loyalty.transactions.single.type, 'earned');
    expect(loyalty.transactions.single.points, 100);
  });

  test('adjustCustomerLoyalty parses the adjustment response', () async {
    final responseData = {
      'success': true,
      'data': {
        'account': {
          'id': 10,
          'customer_id': 5,
          'points_balance': 300,
          'lifetime_earned': 400,
          'lifetime_redeemed': 150,
          'created_at': null,
          'updated_at': null,
        },
        'transaction': {
          'id': 21,
          'customer_loyalty_account_id': 10,
          'customer_id': 5,
          'branch_id': 1,
          'order_id': null,
          'type': 'adjustment',
          'points': 50,
          'balance_after': 300,
          'description': 'Welcome bonus',
          'created_at': null,
          'updated_at': null,
        },
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(
          path: '/customers/5/loyalty/adjust',
        ),
      ),
    );

    final transaction = await repository.adjustCustomerLoyalty(
      customerId: 5,
      points: 50,
      description: 'Welcome bonus',
      branchId: 1,
    );

    expect(transaction.id, 21);
    expect(transaction.type, 'adjustment');
    expect(transaction.points, 50);
    expect(transaction.balanceAfter, 300);
    expect(transaction.description, 'Welcome bonus');
  });

  test('getSettings parses the loyalty settings response', () async {
    final responseData = {
      'success': true,
      'data': {
        'branch_id': 1,
        'is_enabled': true,
        'points_per_currency_unit': '1.5000',
        'points_per_reward_currency_unit': '100.0000',
        'minimum_redeem_points': 100,
        'redemption_enabled': true,
        'expiration_months': 12,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/loyalty/settings'),
      ),
    );

    final settings = await repository.getSettings(branchId: 1);

    expect(settings.branchId, 1);
    expect(settings.isEnabled, isTrue);
    expect(settings.pointsPerCurrencyUnit, 1.5);
    expect(settings.pointsPerRewardCurrencyUnit, 100);
    expect(settings.minimumRedeemPoints, 100);
    expect(settings.redemptionEnabled, isTrue);
    expect(settings.expirationMonths, 12);
  });

  test('updateSettings parses the updated loyalty settings response', () async {
    final responseData = {
      'success': true,
      'data': {
        'branch_id': 1,
        'is_enabled': false,
        'points_per_currency_unit': '2.0000',
        'points_per_reward_currency_unit': '50.0000',
        'minimum_redeem_points': 50,
        'redemption_enabled': false,
        'expiration_months': null,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/loyalty/settings'),
      ),
    );

    final settings = await repository.updateSettings(
      isEnabled: false,
      pointsPerCurrencyUnit: 2,
      pointsPerRewardCurrencyUnit: 50,
      minimumRedeemPoints: 50,
      redemptionEnabled: false,
      expirationMonths: null,
      branchId: 1,
    );

    expect(settings.branchId, 1);
    expect(settings.isEnabled, isFalse);
    expect(settings.pointsPerCurrencyUnit, 2);
    expect(settings.pointsPerRewardCurrencyUnit, 50);
    expect(settings.minimumRedeemPoints, 50);
    expect(settings.redemptionEnabled, isFalse);
    expect(settings.expirationMonths, isNull);
  });
}