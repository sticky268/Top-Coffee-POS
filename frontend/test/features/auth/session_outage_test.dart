import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/session_cache.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/application/auth_state.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';

class _Api extends Mock implements ApiClient {}

class _Cache extends Mock implements SessionCache {}

void main() {
  late _Api api;
  late _Cache cache;
  late ProviderContainer container;

  setUp(() {
    api = _Api();
    cache = _Cache();
    when(() => api.readToken()).thenAnswer((_) async => 'saved-token');
    when(() => api.clearToken()).thenAnswer((_) async {});
    when(() => cache.clear()).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          AuthRepository(api, sessionCache: cache),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  for (final outage in <ApiException>[
    const NetworkException(),
    const ServerException(),
  ]) {
    test(
      '${outage.runtimeType} restores only a valid cached session',
      () async {
        when(() => api.request<Response<dynamic>>(any())).thenThrow(outage);
        when(() => cache.read(token: 'saved-token')).thenAnswer(
          (_) async => {
            'id': 7,
            'name': 'Cashier',
            'email': 'cashier@example.test',
            'roles': ['cashier'],
            'permissions': ['orders.create'],
            'branches': [
              {'id': 2, 'name': 'Cafe', 'code': 'PP-02'},
            ],
          },
        );

        await container.read(authControllerProvider.notifier).initialization;

        final state = container.read(authControllerProvider);
        expect(state, isA<AuthAuthenticated>());
        expect((state as AuthAuthenticated).user.id, 7);
        verifyNever(() => api.clearToken());
        verifyNever(() => cache.clear());
      },
    );

    test(
        '${outage.runtimeType} preserves credentials without granting access '
        'when no valid cache exists', () async {
      when(() => api.request<Response<dynamic>>(any())).thenThrow(outage);
      when(() => cache.read(token: 'saved-token'))
          .thenAnswer((_) async => null);

      await container.read(authControllerProvider.notifier).initialization;

      expect(
        container.read(authControllerProvider),
        isA<AuthUnauthenticated>(),
      );
      verifyNever(() => api.clearToken());
      verifyNever(() => cache.clear());
    });
  }

  test(
    'a rejected session clears credentials and never falls back to cache',
    () async {
      when(() => api.request<Response<dynamic>>(any()))
          .thenThrow(const AuthException());

      await container.read(authControllerProvider.notifier).initialization;

      expect(
        container.read(authControllerProvider),
        isA<AuthUnauthenticated>(),
      );
      verifyNever(() => cache.read(token: any(named: 'token')));
      verify(() => api.clearToken()).called(1);
      verify(() => cache.clear()).called(1);
    },
  );
}
