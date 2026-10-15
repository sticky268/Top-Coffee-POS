import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/offline/journal_cipher.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/core/storage/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('journal payloads are encrypted at rest and survive a fresh store', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final store = SqliteLocalStore(database);
    const payload = '{"customer":"PRIVATE CUSTOMER","total":12.50,"items":["កាហ្វេ"]}';
    await store.write('order:1:2:a', payload);
    final raw = (await database.customSelect('SELECT value FROM offline_entries').get()).single.read<String>('value');
    expect(raw.startsWith(JournalCipher.prefix), isTrue);
    expect(raw, isNot(contains('PRIVATE CUSTOMER')));
    expect(raw, isNot(contains('12.50')));
    expect(await SqliteLocalStore(database).read('order:1:2:a'), payload);
    await store.write('order:1:2:a', payload);
    final second = (await database.customSelect('SELECT value FROM offline_entries').get()).single.read<String>('value');
    expect(second, isNot(raw), reason: 'Each write needs a fresh nonce.');
  });

  test('legacy plaintext migrates without changing scoped queue records', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('CREATE TABLE offline_entries (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
    await database.customStatement('INSERT INTO offline_entries VALUES (?, ?)', ['order:1:2:a', '{"uuid":"original","status":"pending"}']);
    final store = SqliteLocalStore(database);
    expect(await store.entries('order:1:2:'), {'order:1:2:a': '{"uuid":"original","status":"pending"}'});
    final raw = (await database.customSelect('SELECT value FROM offline_entries').get()).single.read<String>('value');
    expect(raw.startsWith(JournalCipher.prefix), isTrue);
    expect(await SqliteLocalStore(database).read('order:1:2:a'), contains('original'));
  });

  test('ciphertext cannot move to another cashier or branch and failure preserves evidence', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final store = SqliteLocalStore(database);
    await store.write('order:1:2:a', 'paid evidence');
    final raw = (await database.customSelect('SELECT value FROM offline_entries').get()).single.read<String>('value');
    await database.customStatement('INSERT INTO offline_entries VALUES (?, ?)', ['order:9:8:a', raw]);
    await expectLater(store.read('order:9:8:a'), throwsA(isA<Exception>()));
    expect(await store.read('order:1:2:a'), 'paid evidence');
    expect((await database.customSelect('SELECT COUNT(*) AS n FROM offline_entries').get()).single.read<int>('n'), 2);
  });

  test('modified ciphertext and a missing key never become an empty recovered queue', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final store = SqliteLocalStore(database);
    await store.write('order:1:2:a', 'original evidence');
    final raw = (await database.customSelect('SELECT value FROM offline_entries').get()).single.read<String>('value');
    final json = jsonDecode(raw.substring(JournalCipher.prefix.length)) as Map<String, dynamic>;
    final bytes = base64Decode(json['data'] as String); bytes[0] ^= 1;
    json['data'] = base64Encode(bytes);
    await database.customStatement('UPDATE offline_entries SET value = ?', [JournalCipher.prefix + jsonEncode(json)]);
    await expectLater(SqliteLocalStore(database).read('order:1:2:a'), throwsA(isA<Exception>()));
    FlutterSecureStorage.setMockInitialValues({});
    await expectLater(SqliteLocalStore(database).read('order:1:2:a'), throwsA(isA<StateError>()));
    expect((await database.customSelect('SELECT COUNT(*) AS n FROM offline_entries').get()).single.read<int>('n'), 1);
  });
}
