import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/env.dart';

/// Short-lived, device-protected snapshot. Server authorization is rechecked on
/// every replay; offline access never turns a queued order into a paid sale.
class SessionCache {
  SessionCache({FlutterSecureStorage? storage, DateTime Function()? now})
      : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  static const _key = 'offline_session_v1:${Env.apiBaseUrl}';
  static const maxAge = Duration(hours: 8);

  Future<void> save(Map<String, dynamic> user, {required String token}) =>
      _storage.write(
          key: _key,
          value: jsonEncode({
            'saved_at': _now().toUtc().toIso8601String(),
            'user': user,
            'token': token
          }));

  Future<Map<String, dynamic>?> read({required String token}) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final snapshot = jsonDecode(raw) as Map<String, dynamic>;
      if (token.isEmpty || snapshot['token'] != token) return null;
      final age = _now()
          .toUtc()
          .difference(DateTime.parse(snapshot['saved_at'] as String));
      if (age.isNegative || age >= maxAge) return null;
      return Map<String, dynamic>.from(snapshot['user'] as Map);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
