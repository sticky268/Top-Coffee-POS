import '../domain/auth_models.dart';

/// App-wide authentication state, driven by [AuthController].
sealed class AuthState {
  const AuthState();
}

/// Nothing has happened yet — before session restoration starts.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Restoring a stored session, or a login/logout call is in flight.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AuthenticatedUser user;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// A login attempt failed. Distinct from [AuthUnauthenticated] so the login
/// screen can show a message, while the router still treats it as "not
/// authenticated" for redirect purposes.
class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}
