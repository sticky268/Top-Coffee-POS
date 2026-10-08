import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';

class MemoryStore implements LocalStore {
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

void main() {
  test('restart preserves exact request UUID and original payload', () async {
    final store = MemoryStore();
    final first = OrderOutbox(store, newUuid: () => 'original');
    final saved = await first
        .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {
      'branch_id': 2,
      'items': [
        {'product_id': 3, 'quantity': 2}
      ]
    });
    await first.finish(saved, error: const NetworkException());
    await first.close();
    final restarted = OrderOutbox(store, newUuid: () => 'new');
    addTearDown(restarted.close);
    final retry = await restarted
        .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {
      'branch_id': 2,
      'items': [
        {'product_id': 3, 'quantity': 2}
      ]
    });
    expect(retry.uuid, 'original');
    expect(retry.payload, saved.payload);
    expect(retry.payload['expected_cashier_id'], 1);
  });

  test('different users and branches never see or reuse another queue',
      () async {
    var next = 0;
    final outbox = OrderOutbox(MemoryStore(), newUuid: () => '${next++}');
    addTearDown(outbox.close);
    await outbox
        .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {});
    expect(await outbox.list(2, 2), isEmpty);
    expect(await outbox.list(1, 3), isEmpty);
    final other = await outbox
        .prepare(userId: 2, branchId: 2, endpoint: '/orders', payload: {});
    expect(other.uuid, '1');
  });

  test(
      'concurrent identical saves use one durable request; later sale gets new UUID',
      () async {
    var next = 0;
    final outbox = OrderOutbox(MemoryStore(), newUuid: () => '${next++}');
    addTearDown(outbox.close);
    Future<PendingOrder> prepare() => outbox
        .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {});
    final pair = await Future.wait([prepare(), prepare()]);
    expect(pair[0].uuid, pair[1].uuid);
    await outbox.finish(pair[0], orderId: 7);
    expect((await prepare()).uuid, '1');
  });

  test(
      'rejections require review; clearing acknowledged orders keeps uncertain requests',
      () async {
    var next = 0;
    final outbox = OrderOutbox(MemoryStore(), newUuid: () => '${next++}');
    addTearDown(outbox.close);
    final failed = await outbox
        .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {});
    await outbox.finish(failed,
        error: const ValidationException({}, 'Not enough stock'));
    final accepted = await outbox.prepare(
        userId: 1, branchId: 2, endpoint: '/orders', payload: {'items': []});
    await outbox.finish(accepted, orderId: 7);
    await outbox.clearAcknowledged(1, 2);
    final remaining = await outbox.list(1, 2);
    expect(remaining.single.status, 'review');
    expect(remaining.single.error, 'Not enough stock');
    await outbox.retry(remaining.single);
    expect((await outbox.list(1, 2)).single.uuid, failed.uuid);
  });

  test('a failed write prevents submission and does not leave a phantom record',
      () async {
    final outbox = OrderOutbox(_FailingStore());
    addTearDown(outbox.close);
    await expectLater(
        outbox
            .prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {}),
        throwsA(isA<StateError>()));
    expect(await outbox.list(1, 2), isEmpty);
  });

  test('request lock serializes foreground and background sends', () async {
    final outbox = OrderOutbox(MemoryStore());
    addTearDown(outbox.close);
    final release = Completer<void>();
    final events = <String>[];
    final first = outbox.withRequestLock('id', () async {
      events.add('first');
      await release.future;
    });
    final second = outbox.withRequestLock('id', () async {
      events.add('second');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first']);
    release.complete();
    await Future.wait([first, second]);
    expect(events, ['first', 'second']);
  });
}

class _FailingStore extends MemoryStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Disk full');
}
