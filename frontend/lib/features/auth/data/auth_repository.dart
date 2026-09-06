import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';

/// Talks to the /api/v1/auth/* endpoints via the existing [ApiClient].
/// Does not manage app-wide auth *state* — that's [AuthController]'s job
/// (features/auth/application). This class is a thin, testable boundary
/// around the network calls + token persistence.
class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<LoginResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post('/auth/login', data: {
        'email': email,
        'password': password,
        'device_name': deviceName,
      }),
    );

    final result = LoginResult.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );

    await _apiClient.saveToken(result.token);
    return result;
  }

  /// Calls the backend logout (revokes the current token) and always clears
  /// the local token afterwards, even if the network call fails — a stale
  /// server-side token is a lesser problem than a cashier stuck unable to
  /// log out on a device with no signal.
  Future<void> logout() async {
    try {
      await _apiClient.request((dio) => dio.post('/auth/logout'));
    } finally {
      await _apiClient.clearToken();
    }
  }

  Future<AuthenticatedUser> getCurrentUser() async {
    final response = await _apiClient.request((dio) => dio.get('/auth/me'));
    return AuthenticatedUser.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<bool> hasStoredToken() async {
    final token = await _apiClient.readToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearStoredToken() => _apiClient.clearToken();
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});
