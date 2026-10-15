import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../storage/app_database.dart';
import 'journal_cipher.dart';

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> entries(String prefix);
}

class SqliteLocalStore implements LocalStore {
  SqliteLocalStore(this.database, {JournalCipher? cipher})
      : _cipher = cipher ?? JournalCipher();
  final JournalCipher _cipher;
  final AppDatabase database;
  Future<void>? _ready;

  Future<void> _initialize() => _ready ??= _prepare();

  Future<void> _prepare() async {
    await database.customStatement('PRAGMA secure_delete = ON');
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS offline_entries '
      '(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
    );
    final rows = await database
        .customSelect('SELECT key, value FROM offline_entries')
        .get();
    await _cipher.initialize(
        hasEncryptedRows: rows.any((row) =>
            row.read<String>('value').startsWith(JournalCipher.prefix)));
    // Verify existing ciphertext before migrating any legacy record. Failure
    // preserves every row; never interpret corruption as an empty queue.
    for (final row in rows) {
      if (row.read<String>('value').startsWith(JournalCipher.prefix)) {
        await _cipher.open(row.read<String>('key'), row.read<String>('value'));
      }
    }
    final legacy = rows
        .where((row) =>
            !row.read<String>('value').startsWith(JournalCipher.prefix))
        .toList();
    if (legacy.isEmpty) {
      await _cipher.markProtected();
      return;
    }
    if (!_cipher.allowLegacy) {
      throw StateError(
          'Offline record encryption was changed. Keep this device data for review.');
    }
    await database.transaction(() async {
      for (final row in legacy) {
        final key = row.read<String>('key');
        await database.customStatement(
            'UPDATE offline_entries SET value = ? WHERE key = ?',
            [await _cipher.seal(key, row.read<String>('value')), key]);
      }
    });
    // Remove SQLite free-page remnants after the atomic legacy rewrite.
    await database.customStatement('VACUUM');
    await _cipher.markProtected();
  }

  @override
  Future<String?> read(String key) async {
    await _initialize();
    final rows = await database.customSelect(
      'SELECT value FROM offline_entries WHERE key = ?',
      variables: [Variable.withString(key)],
    ).get();
    return rows.isEmpty
        ? null
        : await _cipher.open(key, rows.single.read<String>('value'));
  }

  @override
  Future<void> write(String key, String value) async {
    await _initialize();
    await database.customStatement(
      'INSERT OR REPLACE INTO offline_entries (key, value) VALUES (?, ?)',
      [key, await _cipher.seal(key, value)],
    );
  }

  @override
  Future<void> delete(String key) async {
    await _initialize();
    await database.customStatement(
      'DELETE FROM offline_entries WHERE key = ?',
      [key],
    );
  }

  @override
  Future<Map<String, String>> entries(String prefix) async {
    await _initialize();
    final rows = await database.customSelect(
      'SELECT key, value FROM offline_entries WHERE substr(key, 1, ?) = ?',
      variables: [
        Variable.withInt(prefix.length),
        Variable.withString(prefix),
      ],
    ).get();
    final result = <String, String>{};
    for (final row in rows) {
      final key = row.read<String>('key');
      if (key.startsWith(prefix)) {
        result[key] = await _cipher.open(key, row.read<String>('value'));
      }
    }
    return result;
  }
}

final localStoreProvider = Provider<LocalStore>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return SqliteLocalStore(database);
});
