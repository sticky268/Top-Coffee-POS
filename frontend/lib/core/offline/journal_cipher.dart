import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';

/// Authenticated payload encryption. Row keys remain visible for scoped queries.
class JournalCipher {
  JournalCipher({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  final _algorithm = AesGcm.with256bits();
  SecretKey? _key;
  bool allowLegacy = false;
  static const _markerName = 'journal_protected_v1:${Env.apiBaseUrl}';
  static const prefix = 'posenc:v1:';
  static const _keyName = 'journal_key_v1:${Env.apiBaseUrl}';
  static Future<void> _keyWrites = Future.value();

  Future<void> initialize({required bool hasEncryptedRows}) async {
    // Two journal instances must not create different keys concurrently.
    final next = _keyWrites.then((_) async {
      allowLegacy = await _storage.read(key: _markerName) != '1';
      var encoded = await _storage.read(key: _keyName);
      if (encoded == null) {
        if (hasEncryptedRows || !allowLegacy) {
          throw StateError(
              'Offline data is locked. Its device key is unavailable. Do not clear app data.');
        }
        encoded = base64Encode(
            await (await _algorithm.newSecretKey()).extractBytes());
        await _storage.write(key: _keyName, value: encoded);
        if (await _storage.read(key: _keyName) != encoded) {
          throw StateError('Could not retain the offline data key.');
        }
      }
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) throw StateError('Offline data key is invalid.');
      _key = SecretKey(bytes);
    });
    _keyWrites = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await next;
  }

  Future<void> markProtected() => _storage.write(key: _markerName, value: '1');

  List<int> _context(String row) => utf8.encode('${Env.apiBaseUrl}\u0000$row');

  Future<String> seal(String row, String plaintext) async {
    final box = await _algorithm.encrypt(utf8.encode(plaintext),
        secretKey: _key!, aad: _context(row));
    return prefix +
        jsonEncode({
          'nonce': base64Encode(box.nonce),
          'data': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        });
  }

  Future<String> open(String row, String ciphertext) async {
    if (!ciphertext.startsWith(prefix)) {
      throw StateError('Offline record is not encrypted.');
    }
    final json =
        jsonDecode(ciphertext.substring(prefix.length)) as Map<String, dynamic>;
    final box = SecretBox(base64Decode(json['data'] as String),
        nonce: base64Decode(json['nonce'] as String),
        mac: Mac(base64Decode(json['mac'] as String)));
    return utf8.decode(
        await _algorithm.decrypt(box, secretKey: _key!, aad: _context(row)));
  }
}
