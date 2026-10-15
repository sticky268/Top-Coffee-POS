import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late AuthRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = AuthRepository(apiClient);
    when(() => apiClient.deviceId()).thenAnswer((_) async => '11111111-1111-4111-8111-111111111111');
    when(() => apiClient.readToken()).thenAnswer((_) async => 'stored-token');
  });

  test('a delayed login cannot restore credentials after logout', () async {
    final response = Completer<Response<dynamic>>();
    var calls = 0;
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer((_) {
      if (calls++ == 0) return response.future;
      return Future.value(Response(data: {'success': true},
          requestOptions: RequestOptions(path: '/auth/logout')));
    });
    when(() => apiClient.clearToken()).thenAnswer((_) async {});
    final signingIn = repository.login(email: 'a@b.test', password: 'password', deviceName: 'test');
    await Future<void>.delayed(Duration.zero);
    await repository.logout();
    response.complete(Response(requestOptions: RequestOptions(path: '/auth/login'), data: {
      'data': {'token': 'late-token', 'user': {'id': 1, 'name': 'Old user',
        'email': 'a@b.test', 'roles': ['cashier'], 'permissions': [], 'branches': []}}
    }));
    await expectLater(signingIn, throwsA(isA<AuthException>()));
    verifyNever(() => apiClient.saveToken(any()));
  });

  group('login', () {
    test('saves the Sanctum token and returns the parsed user on success', () async {
      final responseData = {
        'success': true,
        'data': {
          'token': 'abc123',
          'user': {
            'id': 1,
            'name': 'Cashier User',
            'email': 'cashier@topcoffee.test',
            'roles': ['cashier'],
            'permissions': ['orders.create'],
            'branches': [
              {'id': 1, 'name': 'Riverside', 'code': 'PP-01'}
            ],
          },
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/auth/login'),
        ),
      );
      when(() => apiClient.saveToken(any())).thenAnswer((_) async {});

      final result = await repository.login(
        email: 'cashier@topcoffee.test',
        password: 'password',
        deviceName: 'test-device',
      );

      expect(result.token, 'abc123');
      expect(result.user.name, 'Cashier User');
      expect(result.user.roles, ['cashier']);
      expect(result.user.branches.single.code, 'PP-01');
      verify(() => apiClient.saveToken('abc123')).called(1);
    });

    test('throws AuthException on invalid credentials (401)', () async {
      when(() => apiClient.request<Response<dynamic>>(any()))
          .thenThrow(const AuthException('Invalid credentials'));

      expect(
        () => repository.login(email: 'a@b.com', password: 'wrong', deviceName: 'test'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('logout', () {
    test('always clears the local token, even if the network call throws', () async {
      when(() => apiClient.request<Response<dynamic>>(any()))
          .thenThrow(const NetworkException());
      when(() => apiClient.clearToken()).thenAnswer((_) async {});

      // logout() re-throws nothing — network failure shouldn't block a
      // cashier from being logged out locally.
      await expectLater(repository.logout, throwsA(isA<NetworkException>()));
      verify(() => apiClient.clearToken()).called(1);
    });

    test('clears token on a successful backend logout call', () async {
      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: {'success': true},
          requestOptions: RequestOptions(path: '/auth/logout'),
        ),
      );
      when(() => apiClient.clearToken()).thenAnswer((_) async {});

      await repository.logout();
      verify(() => apiClient.clearToken()).called(1);
    });
  });

  group('getCurrentUser', () {
    test('parses the /auth/me response', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 2,
          'name': 'Admin User',
          'email': 'admin@topcoffee.test',
          'roles': ['admin'],
          'permissions': ['branches.view-all'],
          'branches': <Map<String, dynamic>>[],
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: responseData,
          requestOptions: RequestOptions(path: '/auth/me'),
        ),
      );

      final user = await repository.getCurrentUser();

      expect(user.id, 2);
      expect(user.roles, ['admin']);
      expect(user.branches, isEmpty);
    });
  });

  group('hasStoredToken', () {
    test('true when a non-empty token is stored', () async {
      when(() => apiClient.readToken()).thenAnswer((_) async => 'abc');
      expect(await repository.hasStoredToken(), isTrue);
    });

    test('false when no token is stored', () async {
      when(() => apiClient.readToken()).thenAnswer((_) async => null);
      expect(await repository.hasStoredToken(), isFalse);
    });
  });
}
