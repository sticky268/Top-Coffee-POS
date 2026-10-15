import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync_summary.dart';

import '../../support/memory_local_store.dart';

PendingOrder record(String status, {DateTime? confirmedAt}) => PendingOrder(
  uuid: 'request',
  userId: 1,
  branchId: 2,
  endpoint: '/orders',
  payload: const {},
  createdAt: DateTime.utc(2026),
  fingerprint: 'fixture',
  status: status,
  confirmedAt: confirmedAt,
);

void main() {
  test('counts waiting, review and confirmation separately without guessing', () {
    final recent = DateTime.utc(2026, 10, 15, 13);
    final summary = OrderSyncSummary.fromOrders([
      record('pending'),
      record('review'),
      record('unknown'),
      record('synced'),
      record('synced', confirmedAt: DateTime.utc(2026, 10, 15, 12)),
      record('synced', confirmedAt: recent),
    ]);
    expect(summary.waiting, 1);
    expect(summary.needsReview, 2);
    expect(summary.confirmed, 3);
    expect(summary.latestConfirmation, recent);
    expect(summary.hasUnconfirmed, isTrue);
    expect(
      summary.description,
      '1 waiting for server confirmation · 2 needing review',
    );
    final legacy = OrderSyncSummary.fromOrders([record('synced')]);
    expect(legacy.latestConfirmation, isNull);
    expect(legacy.needsAttention, isFalse);
  });

  test('acknowledgement time persists across restart and stale retries', () async {
    final store = MemoryLocalStore();
    var outbox = OrderOutbox(store, newUuid: () => 'original');
    final pending = await outbox.prepare(
      userId: 1,
      branchId: 2,
      endpoint: '/orders',
      payload: {'branch_id': 2},
    );
    await outbox.finish(pending, error: const NetworkException());
    expect((await outbox.list(1, 2)).single.confirmedAt, isNull);
    await outbox.finish(pending, orderId: 42);
    final acknowledged = (await outbox.list(1, 2)).single;
    expect(acknowledged.confirmedAt, isNotNull);
    await outbox.close();

    outbox = OrderOutbox(store);
    addTearDown(outbox.close);
    await outbox.finish(pending, error: const NetworkException());
    await outbox.retry(pending);
    final restored = (await outbox.list(1, 2)).single;
    expect(restored.status, 'synced');
    expect(restored.confirmedAt, acknowledged.confirmedAt);
    expect(await outbox.list(1, 3), isEmpty);
    expect(await outbox.list(2, 2), isEmpty);
  });

  test('legacy JSON loads without inventing a confirmation time', () {
    final json = record('synced').toJson()..remove('confirmed_at');
    final restored = PendingOrder.fromJson(json);
    expect(restored.status, 'synced');
    expect(restored.confirmedAt, isNull);
    expect(OrderSyncSummary.fromOrders([restored]).latestConfirmation, isNull);
  });
}
