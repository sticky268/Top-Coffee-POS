import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

/// Owns app-wide [AuthState]. Restores a stored session on startup (calls
/// /auth/me if a token exists, clearing it if the server rejects it), and
/// exposes login/logout for the UI layer.
///
/// Two production-quality guarantees this class makes:
///  1. [initialization] is a deterministic completion signal for startup
///     restoration — callers (including tests) should await it instead of
///     guessing with delays, since Riverpod providers are lazy and a plain
///     "wait a tick" has no defined relationship to when restoration runs.
///  2. Every `state = ...` assignment that follows an `await` is guarded by
///     [mounted], so a disposed controller (e.g. a torn-down
///     ProviderContainer mid-restoration in a test) can never throw or
///     leak a late state update.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthInitial()) {
    _initialization = _restoreSession();
  }

  final AuthRepository _repository;
  late Future<void> _initialization;

  /// Completes once startup session restoration has finished — successfully
  /// or not — and [state] holds a terminal value ([AuthAuthenticated] or
  /// [AuthUnauthenticated]). Never left resolved while state is still
  /// [AuthLoading].
  Future<void> get initialization => _initialization;

  /// Re-runs session restoration (e.g. a "retry" action after a network
  /// failure). Updates [initialization] to the new attempt.
  Future<void> restoreSession() {
    final future = _restoreSession();
    _initialization = future;
    return future;
  }

  /// Guaranteed to end in [AuthAuthenticated] or [AuthUnauthenticated] —
  /// never left in [AuthLoading]. Any failure (network, server, or even a
  /// secure-storage/platform error) falls back to unauthenticated rather
  /// than an indefinite spinner.
  Future<void> _restoreSession() async {
    if (!mounted) return;
    state = const AuthLoading();

    try {
      final hasToken = await _repository.hasStoredToken();
      if (!mounted) return;

      if (!hasToken) {
        state = const AuthUnauthenticated();
        return;
      }

      final user = await _repository.getCurrentUser();
      if (!mounted) return;
      state = AuthAuthenticated(user);
    } catch (error) {
      // Covers: expired/invalid token (ApiException from getCurrentUser),
      // network/server failure during restoration, and any unexpected
      // error reading the stored token itself. In every case the safe,
      // recoverable outcome is the login screen, not a stuck spinner.
      try {
        if (error is! NetworkException) await _repository.clearStoredToken();
      } catch (_) {
        // Best-effort — if even clearing the token fails, still proceed
        // to Unauthenticated below rather than staying stuck.
      }
      if (!mounted) return;
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    if (!mounted) return;
    state = const AuthLoading();
    try {
      final result = await _repository.login(
        email: email,
        password: password,
        deviceName: deviceName,
      );
      if (!mounted) return;
      state = AuthAuthenticated(result.user);
    } on ApiException catch (e) {
      if (!mounted) return;
      state = AuthError(_messageFor(e));
    } catch (_) {
      if (mounted) {
        state = const AuthError(
            'Could not sign in on this device. Please try again.');
      }
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // AuthRepository.logout() clears the local token in a `finally`
      // block regardless of whether the network call succeeded — a
      // cashier on a device with no signal must still be able to log out.
      // We swallow the error here rather than surfacing it, since the
      // local state below is what actually matters to the UI.
    } finally {
      if (mounted) state = const AuthUnauthenticated();
    }
  }

  String _messageFor(ApiException e) {
    if (e is ValidationException) {
      final first = e.errors.values.isNotEmpty ? e.errors.values.first : null;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first != null) return first.toString();
      return e.message;
    }
    return e.message;
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
