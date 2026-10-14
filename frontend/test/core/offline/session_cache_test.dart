import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/offline/session_cache.dart';

class MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('offline session expires, rejects clock rollback, and clears on logout',
      () async {
    final storage = MockStorage();
    var now = DateTime.utc(2026, 10, 8);
    String? value;
    when(() =>
            storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer(
            (call) async => value = call.namedArguments[#value] as String?);
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => value);
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {
      value = null;
    });
    final cache = SessionCache(storage: storage, now: () => now);
    await cache.save({'id': 1}, token: 'session-one');
    expect((await cache.read(token: 'session-one'))!['id'], 1);
    expect(await cache.read(token: 'different-login'), isNull);
    now = now.subtract(const Duration(minutes: 1));
    expect(await cache.read(token: 'session-one'), isNull);
    now = now.add(const Duration(hours: 8, minutes: 1));
    expect(await cache.read(token: 'session-one'), isNull);
    await cache.clear();
    expect(value, isNull);
  });
}
