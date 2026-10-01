import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/subscription/data/subscription_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockApiClient apiClient;
  late SubscriptionRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = SubscriptionRepository(apiClient);
  });

  group('getSubscription', () {
    test('parses the exact GET /api/v1/subscription response shape', () async {
      final responseData = {
        'success': true,
        'data': {
          'plan': {
            'id': 1,
            'name': '1 Branch',
            'slug': '1-branch',
            'branch_limit': 1,
            'price': '0.00',
            'billing_interval': 'monthly',
            'is_active': true,
          },
          'branch_usage': {
            'current': 1,
            'limit': 1,
            'remaining': 0,
          },
          'subscription': {
            'status': 'trial',
            'started_at': '2026-09-29T10:00:00+00:00',
            'expires_at': null,
            'is_active': true,
            'is_expired': false,
            'can_modify': true,
          },
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/subscription'),
        ),
      );

      final details = await repository.getSubscription();

      expect(details.plan, isNotNull);
      expect(details.plan!.id, 1);
      expect(details.plan!.name, '1 Branch');
      expect(details.plan!.slug, '1-branch');
      expect(details.plan!.branchLimit, 1);
      expect(details.plan!.price, 0.0);
      expect(details.plan!.billingInterval, 'monthly');
      expect(details.plan!.isActive, isTrue);

      expect(details.branchUsage.current, 1);
      expect(details.branchUsage.limit, 1);
      expect(details.branchUsage.remaining, 0);

      expect(details.subscription.status, 'trial');
      expect(details.subscription.startedAt, isNotNull);
      expect(details.subscription.expiresAt, isNull);
      expect(details.subscription.isActive, isTrue);
      expect(details.subscription.isExpired, isFalse);
      expect(details.subscription.canModify, isTrue);

      expect(details.canModify, isTrue);
      expect(details.isReadOnly, isFalse);
      expect(details.isExpired, isFalse);
      expect(details.isSuspended, isFalse);
    });

    test('parses an expired subscription as read-only', () async {
      final responseData = {
        'success': true,
        'data': {
          'plan': {
            'id': 5,
            'name': '5 Branches',
            'slug': '5-branches',
            'branch_limit': 5,
            'price': '0.00',
            'billing_interval': 'monthly',
            'is_active': true,
          },
          'branch_usage': {
            'current': 3,
            'limit': 5,
            'remaining': 2,
          },
          'subscription': {
            'status': 'expired',
            'started_at': '2026-08-01T10:00:00+00:00',
            'expires_at': '2026-09-01T10:00:00+00:00',
            'is_active': false,
            'is_expired': true,
            'can_modify': false,
          },
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/subscription'),
        ),
      );

      final details = await repository.getSubscription();

      expect(details.plan!.branchLimit, 5);
      expect(details.branchUsage.current, 3);
      expect(details.branchUsage.remaining, 2);

      expect(details.subscription.status, 'expired');
      expect(details.subscription.isActive, isFalse);
      expect(details.subscription.isExpired, isTrue);
      expect(details.subscription.canModify, isFalse);

      expect(details.canModify, isFalse);
      expect(details.isReadOnly, isTrue);
      expect(details.isExpired, isTrue);
      expect(details.isSuspended, isFalse);
    });

    test('parses a suspended subscription as read-only', () async {
      final responseData = {
        'success': true,
        'data': {
          'plan': null,
          'branch_usage': {
            'current': 2,
            'limit': null,
            'remaining': null,
          },
          'subscription': {
            'status': 'suspended',
            'started_at': null,
            'expires_at': null,
            'is_active': false,
            'is_expired': false,
            'can_modify': false,
          },
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/subscription'),
        ),
      );

      final details = await repository.getSubscription();

      expect(details.plan, isNull);
      expect(details.branchUsage.current, 2);
      expect(details.branchUsage.limit, isNull);
      expect(details.branchUsage.remaining, isNull);

      expect(details.subscription.status, 'suspended');
      expect(details.subscription.isActive, isFalse);
      expect(details.subscription.isExpired, isFalse);
      expect(details.subscription.canModify, isFalse);

      expect(details.canModify, isFalse);
      expect(details.isReadOnly, isTrue);
      expect(details.isSuspended, isTrue);
    });

    test('supports an active subscription with an expiry date', () async {
      final responseData = {
        'success': true,
        'data': {
          'plan': {
            'id': 10,
            'name': '10 Branches',
            'slug': '10-branches',
            'branch_limit': 10,
            'price': '25.00',
            'billing_interval': 'monthly',
            'is_active': true,
          },
          'branch_usage': {
            'current': 4,
            'limit': 10,
            'remaining': 6,
          },
          'subscription': {
            'status': 'active',
            'started_at': '2026-09-01T10:00:00+00:00',
            'expires_at': '2026-10-01T10:00:00+00:00',
            'is_active': true,
            'is_expired': false,
            'can_modify': true,
          },
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/subscription'),
        ),
      );

      final details = await repository.getSubscription();

      expect(details.plan!.name, '10 Branches');
      expect(details.plan!.price, 25.0);
      expect(details.branchUsage.current, 4);
      expect(details.branchUsage.limit, 10);
      expect(details.branchUsage.remaining, 6);

      expect(details.subscription.status, 'active');
      expect(details.subscription.isActive, isTrue);
      expect(details.subscription.isExpired, isFalse);
      expect(details.subscription.canModify, isTrue);
      expect(details.isReadOnly, isFalse);
    });

    test('propagates API exceptions', () async {
      final exception = Exception('Subscription request failed');

      when(() => apiClient.request<Response<dynamic>>(any()))
          .thenThrow(exception);

      expect(
        () => repository.getSubscription(),
        throwsA(same(exception)),
      );
    });

    test('requests the subscription endpoint with GET /subscription', () async {
      final mockDio = MockDio();

      when(() => mockDio.get<dynamic>('/subscription')).thenAnswer(
        (_) async => Response(
          data: {
            'success': true,
            'data': {
              'plan': null,
              'branch_usage': {
                'current': 0,
                'limit': null,
                'remaining': null,
              },
              'subscription': {
                'status': 'trial',
                'started_at': null,
                'expires_at': null,
                'is_active': true,
                'is_expired': false,
                'can_modify': true,
              },
            },
          },
          requestOptions: RequestOptions(path: '/subscription'),
        ),
      );

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (invocation) async {
          final call = invocation.positionalArguments[0]
              as Future<Response<dynamic>> Function(Dio);

          return call(mockDio);
        },
      );

      await repository.getSubscription();

      verify(() => mockDio.get<dynamic>('/subscription')).called(1);
    });
  });
}
