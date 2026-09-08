/// Domain models for authentication. These mirror the shape returned by
/// `POST /api/v1/auth/login`, `GET /api/v1/auth/me` (see
/// backend/app/Http/Controllers/Api/V1/Auth/AuthController.php).
library;

class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.name,
    required this.code,
  });

  final int id;
  final String name;
  final String code;

  factory BranchSummary.fromJson(Map<String, dynamic> json) {
    return BranchSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
    );
  }
}

/// The authenticated user plus their roles/permissions/branches, as
/// returned by both /auth/login (nested under `user`) and /auth/me.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.roles,
    required this.permissions,
    required this.branches,
  });

  final int id;
  final String name;
  final String email;
  final List<String> roles;
  final List<String> permissions;
  final List<BranchSummary> branches;

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      roles: List<String>.from(json['roles'] as List? ?? const []),
      permissions: List<String>.from(json['permissions'] as List? ?? const []),
      branches: (json['branches'] as List? ?? const [])
          .map((b) => BranchSummary.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  bool hasRole(String role) => roles.contains(role);
  bool hasPermission(String permission) => permissions.contains(permission);
}

/// Result of a successful login call: the Sanctum token plus the user.
class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final AuthenticatedUser user;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      token: json['token'] as String,
      user: AuthenticatedUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
