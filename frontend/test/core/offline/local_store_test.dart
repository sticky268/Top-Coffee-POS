import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/core/storage/app_database.dart';

void main() {
  test('SQLite journal supports durable replace, scoped reads and deletion',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final first = SqliteLocalStore(database);
    await first.write('order:1:2:a', 'pending');
    await first.write('order:1:3:b', 'other branch');
    final reopened = SqliteLocalStore(database);
    expect(await reopened.read('order:1:2:a'), 'pending');
    await reopened.write('order:1:2:a', 'confirmed');
    expect(await first.entries('order:1:2:'), {'order:1:2:a': 'confirmed'});
    await first.delete('order:1:2:a');
    expect(await reopened.read('order:1:2:a'), isNull);
    expect(await reopened.read('order:1:3:b'), 'other branch');
  });
}
