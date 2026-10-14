import 'package:top_coffee_pos/core/offline/local_store.dart';

class MemoryLocalStore implements LocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> entries(String prefix) async => {
        for (final entry in values.entries)
          if (entry.key.startsWith(prefix)) entry.key: entry.value,
      };
}
