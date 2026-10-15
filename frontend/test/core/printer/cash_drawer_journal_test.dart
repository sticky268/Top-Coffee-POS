import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/printer/cash_drawer_journal.dart';

import '../../support/memory_local_store.dart';

void main() {
  const selected = (userId: 7, branchId: 8);
  late MemoryLocalStore store;
  late CashDrawerJournal journal;

  setUp(() {
    store = MemoryLocalStore();
    journal = CashDrawerJournal(store);
  });
  tearDown(() => journal.dispose());

  test('manual reasons are required and evidence survives journal recreation', () async {
    await expectLater(journal.begin(selected), throwsStateError);
    await expectLater(journal.begin(selected, reason: '  '), throwsStateError);
    expect(store.values, isEmpty);
    final event = await journal.begin(selected, reason: '  Make change  ');
    await journal.save(event.finish('command_sent'));
    final restarted = CashDrawerJournal(store);
    addTearDown(restarted.dispose);
    final saved = (await restarted.pending(selected)).single;
    expect(saved.id, event.id);
    expect(saved.reason, 'Make change');
    expect(saved.source, 'manual');
    expect(saved.status, 'command_sent');
    expect(saved.toJson().containsKey('physical_open_confirmed'), isFalse);
    expect(saved.toJson()['expected_user_id'], 7);
    expect(saved.toJson().containsKey('order_id'), isFalse);
  });

  test('offline upload retains evidence and retries once without duplicating history', () async {
    final event = await journal.begin(selected, orderId: 91);
    await journal.save(event.finish('unconfirmed'));
    var offline = true;
    final uploads = <CashDrawerEvent>[];
    final sync = CashDrawerSync(journal, () => selected, (event) async {
      if (offline) throw StateError('Offline');
      uploads.add(event);
    });
    await sync.sync(force: true);
    expect(await journal.pending(selected), hasLength(1));
    offline = false;
    await sync.sync(force: true);
    await sync.sync(force: true);
    expect(uploads, hasLength(1));
    expect(uploads.single.orderId, 91);
    expect(uploads.single.source, 'cash_sale');
    expect(await journal.pending(selected), isEmpty);
    expect(await journal.list(selected), hasLength(1));
  });

  test('acknowledging an initial upload cannot lose a newer command result', () async {
    final initial = await journal.begin(selected, reason: 'Count cash');
    final request = Completer<void>();
    final uploads = <String>[];
    final sync = CashDrawerSync(journal, () => selected, (event) async {
      uploads.add(event.status);
      if (event.status == 'attempt_recorded') await request.future;
    });
    final running = sync.sync(force: true);
    // Allow pending evidence to reach the simulated network call.
    await Future<void>.delayed(Duration.zero);
    await journal.save(initial.finish('command_sent'));
    request.complete();
    await running;
    expect((await journal.pending(selected)).single.status, 'command_sent');
    await sync.sync(force: true);
    expect(uploads, ['attempt_recorded', 'command_sent']);
    expect(await journal.pending(selected), isEmpty);
  });

  test('only the selected cashier and branch can upload their local evidence', () async {
    await journal.begin(selected, reason: 'Count cash');
    await journal.begin((userId: 9, branchId: 8), reason: 'Other cashier');
    await journal.begin((userId: 7, branchId: 10), reason: 'Other branch');
    DrawerScope? current = selected;
    final uploads = <CashDrawerEvent>[];
    final sync = CashDrawerSync(journal, () => current, (event) async {
      uploads.add(event);
      current = null;
    });
    await sync.sync(force: true);
    expect(uploads, hasLength(1));
    expect(uploads.single.scope, selected);
    expect(await journal.pending((userId: 9, branchId: 8)), hasLength(1));
    expect(await journal.pending((userId: 7, branchId: 10)), hasLength(1));
    await sync.sync(force: true);
    expect(uploads, hasLength(1));
  });

  test('network failure applies backoff instead of retrying each journal change', () async {
    await journal.begin(selected, reason: 'Count cash');
    var calls = 0;
    final sync = CashDrawerSync(journal, () => selected, (event) async {
      calls++;
      throw StateError('Offline');
    });
    await sync.sync();
    await sync.sync();
    await sync.sync();
    expect(calls, 1);
    expect(await journal.pending(selected), hasLength(1));
  });
}
