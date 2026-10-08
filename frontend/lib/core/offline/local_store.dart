import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../storage/app_database.dart';

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> entries(String prefix);
}

class SqliteLocalStore implements LocalStore {
  SqliteLocalStore(this.database);
  final AppDatabase database;
  Future<void>? _ready;

  Future<void> _initialize() => _ready ??= database.customStatement(
        'CREATE TABLE IF NOT EXISTS offline_entries '
        '(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
      );

  @override
  Future<String?> read(String key) async {
    await _initialize();
    final rows = await database.customSelect(
      'SELECT value FROM offline_entries WHERE key = ?',
      variables: [Variable.withString(key)],
    ).get();
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  @override
  Future<void> write(String key, String value) async {
    await _initialize();
    await database.customStatement(
      'INSERT OR REPLACE INTO offline_entries (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  @override
  Future<void> delete(String key) async {
    await _initialize();
    await database
        .customStatement('DELETE FROM offline_entries WHERE key = ?', [key]);
  }

  @override
  Future<Map<String, String>> entries(String prefix) async {
    await _initialize();
    final rows = await database
        .customSelect('SELECT key, value FROM offline_entries')
        .get();
    return {
      for (final row in rows)
        if (row.read<String>('key').startsWith(prefix))
          row.read<String>('key'): row.read<String>('value'),
    };
  }
}

final localStoreProvider = Provider<LocalStore>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return SqliteLocalStore(database);
});
