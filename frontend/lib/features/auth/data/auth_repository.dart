import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/offline/session_cache.dart';
import '../domain/auth_models.dart';

/// Talks to the /api/v1/auth/* endpoints via the existing [ApiClient].
/// Does not manage app-wide auth *state* — that's [AuthController]'s job
/// (features/auth/application). This class is a thin, testable boundary
/// around the network calls + token persistence.
class AuthRepository {
  AuthRepository(this._apiClient, {SessionCache? sessionCache})
      : _sessionCache = sessionCache;

  final ApiClient _apiClient;
  final SessionCache? _sessionCache;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<T> _sessionWrite<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<LoginResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final revision = ++_revision;
    final deviceId = await _apiClient.deviceId();
    if (revision != _revision) {
      throw const AuthException('Sign-in was cancelled.');
    }
    final response = await _apiClient.request(
      (dio) => dio.post('/auth/login', data: {
        'email': email,
        'password': password,
        'device_name': deviceName,
        'device_id': deviceId,
      }),
    );

    final result = LoginResult.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );

    await _sessionWrite(() async {
      if (revision != _revision) {
        throw const AuthException('Sign-in was cancelled.');
      }
      await _apiClient.saveToken(result.token);
      if (_sessionCache != null) {
        try {
          await _sessionCache.save(
              Map<String, dynamic>.from(response.data['data']['user'] as Map),
              token: result.token);
        } catch (_) {
          /* Online login remains usable if its optional cache fails. */
        }
      }
    });
    return result;
  }

  /// Calls the backend logout (revokes the current token) and always clears
  /// the local token afterwards, even if the network call fails — a stale
  /// server-side token is a lesser problem than a cashier stuck unable to
  /// log out on a device with no signal.
  Future<void> logout() async {
    final revision = ++_revision;
    try {
      final token = await _apiClient.readToken();
      if (token != null && revision == _revision) {
        await _apiClient.request((dio) => dio.post('/auth/logout',
            options: Options(headers: {'Authorization': 'Bearer $token'})));
      }
    } finally {
      await _sessionWrite(() async {
        if (revision != _revision) return;
        try {
          await _apiClient.clearToken();
        } finally {
          await _sessionCache?.clear();
        }
      });
    }
  }

  Future<AuthenticatedUser> getCurrentUser() async {
    final revision = _revision;
    final token = await _apiClient.readToken() ?? '';
    try {
      final response = await _apiClient.request((dio) => dio.get('/auth/me'));
      if (revision != _revision) throw const AuthException('Session changed.');
      final json = response.data['data'] as Map<String, dynamic>;
      if (_sessionCache != null) {
        try {
          await _sessionCache.save(json, token: token);
        } catch (_) {
          /* A valid server session does not depend on cached access. */
        }
      }
      return AuthenticatedUser.fromJson(json);
    } on NetworkException {
      if (revision != _revision) throw const AuthException('Session changed.');
      final cached =
          _sessionCache == null ? null : await _sessionCache.read(token: token);
      if (cached != null) return AuthenticatedUser.fromJson(cached);
      rethrow;
    }
  }

  Future<bool> hasStoredToken() async {
    final token = await _apiClient.readToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearStoredToken() {
    ++_revision;
    return _sessionWrite(() async {
      await _apiClient.clearToken();
      await _sessionCache?.clear();
    });
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider),
      sessionCache: SessionCache());
});
