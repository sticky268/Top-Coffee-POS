import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import '../../support/memory_local_store.dart';

class FakePrinter extends PrinterService {
  bool failConnect = false, loseConfirmation = false;
  Future<void> Function()? connecting;
  final sent = <Map<String, dynamic>>[];
  int connections = 0;
  int drawerPulses = 0;
  @override
  Future<void> openCashDrawer() async {
    drawerPulses++;
    if (loseConfirmation) throw StateError('Drawer confirmation lost');
  }
  @override
  Future<void> connect(String ip) async {
    connections++;
    if (failConnect) throw StateError('Printer unreachable');
    await connecting?.call();
  }

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    sent.add(payload);
    if (loseConfirmation) throw StateError('Printer response lost');
  }

  @override
  Future<void> disconnect() async {}
}

void main() {
  const selected = (userId: 16, branchId: 21);
  late PrintScope? current;
  late MemoryLocalStore store;
  late FakePrinter printer;
  late PrintQueue queue;
  PrintQueue makeQueue() =>
      PrintQueue(store, printer, () => current, (_) async => '192.168.1.10');
  Future<PrintJob> enqueue({Map<String, dynamic>? payload}) => queue.enqueue(
    selected: selected,
    documentId: 'receipt:124',
    reference: 'PP-01-000121',
    branchCode: 'PP-01',
    payload:
        payload ??
        {
          'total': '5.00',
          'documentTitle': '',
          'items': [
            {'name': 'កាហ្វេ', 'quantity': 1},
          ],
        },
  );
  setUp(() {
    current = selected;
    store = MemoryLocalStore();
    printer = FakePrinter();
    queue = makeQueue();
  });
  tearDown(() => queue.dispose());

  test('drawer command is never journaled or automatically replayed', () async {
    printer.loseConfirmation = true;
    await expectLater(queue.openCashDrawer(selected, () async => 'ip', () {}), throwsStateError);
    expect(printer.drawerPulses, 1);
    expect(await queue.list(selected), isEmpty);
    await queue.resumeWaiting(selected);
    expect(printer.drawerPulses, 1);
  });

  test('branch switch during drawer connection prevents the pulse', () async {
    printer.connecting = () async { current = (userId: 16, branchId: 22); };
    await expectLater(queue.openCashDrawer(selected, () async => 'ip', () {}), throwsStateError);
    expect(printer.drawerPulses, 0);
  });

  test('drawer permission is checked again after connection', () async {
    var allowed = true;
    printer.connecting = () async { allowed = false; };
    await expectLater(queue.openCashDrawer(selected, () async => 'ip', () {
      if (!allowed) throw StateError('Not permitted');
    }), throwsStateError);
    expect(printer.drawerPulses, 0);
  });

  test('drawer and receipt commands share one printer serializer', () async {
    final job = await enqueue();
    await Future.wait([
      queue.send(job.id, selected),
      queue.openCashDrawer(selected, () async => 'ip', () {}),
    ]);
    expect(printer.sent, hasLength(1));
    expect(printer.drawerPulses, 1);
    expect((await queue.list(selected)).single.status, PrintStatus.sent);
  });

  test(
    'repeated enqueue and send taps share one durable original print',
    () async {
      final jobs = await Future.wait([enqueue(), enqueue()]);
      expect(jobs[0].id, jobs[1].id);
      await Future.wait([
        queue.send(jobs[0].id, selected),
        queue.send(jobs[1].id, selected),
      ]);
      expect(printer.sent, hasLength(1));
      expect((await queue.list(selected)).single.status, PrintStatus.sent);
    },
  );
  test(
    'failed connection survives recreation and retries the saved snapshot',
    () async {
      printer.failConnect = true;
      final job = await enqueue();
      expect((await queue.send(job.id, selected)).status, PrintStatus.failed);
      final restarted = makeQueue();
      addTearDown(restarted.dispose);
      await restarted.resumeWaiting(selected);
      expect(printer.sent, isEmpty); // Failed jobs require an explicit retry.
      printer.failConnect = false;
      expect((await restarted.send(job.id, selected)).status, PrintStatus.sent);
      expect(printer.sent.single['total'], '5.00');
    },
  );
  test('never-attempted waiting jobs resume after recreation', () async {
    await enqueue();
    final restarted = makeQueue();
    addTearDown(restarted.dispose);
    await restarted.resumeWaiting(selected);
    expect(printer.sent, hasLength(1));
    await restarted.resumeWaiting(selected);
    expect(printer.sent, hasLength(1));
  });
  test(
    'lost printer confirmation is not retried; explicit reprint says COPY',
    () async {
      printer.loseConfirmation = true;
      final job = await enqueue();
      expect(
        (await queue.send(job.id, selected)).status,
        PrintStatus.uncertain,
      );
      await queue.send(job.id, selected);
      await queue.resumeWaiting(selected);
      expect(printer.sent, hasLength(1));
      final copy = await queue.copy(job.id, selected);
      expect((await queue.copy(job.id, selected)).id, copy.id);
      expect(copy.isCopy, isTrue);
      expect(copy.payload['documentTitle'], 'COPY');
      printer.loseConfirmation = false;
      await queue.send(copy.id, selected);
      expect(printer.sent, hasLength(2));
      expect(printer.sent.last['documentTitle'], 'COPY');
    },
  );
  test(
    'interrupted sending recovers as uncertain and never automatically prints',
    () async {
      final job = await enqueue();
      store.values[store.values.keys.single] = jsonEncode(
        job.change({
          'status': PrintStatus.sending.name,
          'attempts': 1,
        }).toJson(),
      );
      final restarted = makeQueue();
      addTearDown(restarted.dispose);
      await restarted.resumeWaiting(selected);
      expect(
        (await restarted.list(selected)).single.status,
        PrintStatus.uncertain,
      );
      expect(printer.sent, isEmpty);
    },
  );
  test('another account or branch cannot read or send these jobs', () async {
    final job = await enqueue();
    current = (userId: 17, branchId: 21);
    expect(await queue.list(current!), isEmpty);
    await expectLater(queue.send(job.id, current!), throwsStateError);
    current = (userId: 16, branchId: 22);
    expect(await queue.list(current!), isEmpty);
    await expectLater(queue.send(job.id, selected), throwsStateError);
    expect(printer.sent, isEmpty);
  });
  test('scope switching while connecting stops transmission', () async {
    printer.connecting = () async {
      current = (userId: 16, branchId: 22);
    };
    final job = await enqueue();
    expect((await queue.send(job.id, selected)).status, PrintStatus.failed);
    expect(printer.sent, isEmpty);
  });
  test('job payload is immutable and logos survive persistence', () async {
    final payload = <String, dynamic>{
      'logoBytes': Uint8List.fromList([1, 2, 3]),
      'items': [
        {'name': 'Original', 'quantity': 1},
      ],
      'total': '5.00',
    };
    final job = await enqueue(payload: payload);
    (payload['items'] as List).clear();
    await queue.send(job.id, selected);
    expect(printer.sent.single['logoBytes'], isA<Uint8List>());
    expect(printer.sent.single['logoBytes'], [1, 2, 3]);
    expect(printer.sent.single['items'], hasLength(1));
  });
  test(
    'a revised receipt after a sent original is visibly marked COPY',
    () async {
      final job = await enqueue();
      await queue.send(job.id, selected);
      final revised = await enqueue(
        payload: {
          'total': '5.00',
          'refunded': '5.00',
          'netPaid': '0.00',
          'documentTitle': '',
        },
      );
      expect(revised.isCopy, isTrue);
      expect(revised.payload['documentTitle'], 'COPY');
      await queue.send(revised.id, selected);
      expect(printer.sent.last['netPaid'], '0.00');
    },
  );
  test(
    'retrying an older failed version cannot send a second unlabelled original',
    () async {
      final old = await enqueue();
      printer.failConnect = true;
      await queue.send(old.id, selected);
      final updated = await enqueue(
        payload: {
          'total': '5.00',
          'refunded': '5.00',
          'netPaid': '0.00',
          'documentTitle': '',
        },
      );
      printer.failConnect = false;
      await queue.send(updated.id, selected);
      final retry = await queue.send(old.id, selected);
      expect(retry.status, PrintStatus.uncertain);
      expect(printer.sent, hasLength(1));
      final copy = await queue.copy(old.id, selected);
      expect(copy.payload['documentTitle'], 'COPY');
    },
  );

  test(
    'legacy receipt can be explicitly reprinted as COPY without an original job',
    () async {
      final copies = await Future.wait([
        queue.enqueue(
          selected: selected,
          documentId: 'receipt:legacy',
          reference: '9',
          payload: {'total': '5.00', 'documentTitle': ''},
          asCopy: true,
        ),
        queue.enqueue(
          selected: selected,
          documentId: 'receipt:legacy',
          reference: '9',
          payload: {'total': '5.00', 'documentTitle': ''},
          asCopy: true,
        ),
      ]);
      expect(copies.first.id, copies.last.id);
      expect(copies.first.isCopy, isTrue);
      await queue.send(copies.first.id, selected);
      expect(printer.sent.single['documentTitle'], 'COPY');
    },
  );

  test('receipt jobs share one stored logo asset in the same scope', () async {
    final payload = <String, dynamic>{
      'logoBytes': Uint8List.fromList([1, 2, 3]),
      'total': '5.00',
    };
    await enqueue(payload: payload);
    await queue.enqueue(
      selected: selected,
      documentId: 'receipt:another',
      reference: '122',
      payload: payload,
    );
    expect(await store.entries('print-asset:'), hasLength(1));
    expect(await queue.list(selected), hasLength(2));
  });

  test(
    'scope switch during persisted logo loading also stops transmission',
    () async {
      final assetStore = SwitchingAssetStore(() {
        current = (userId: 16, branchId: 22);
      });
      final guarded = PrintQueue(
        assetStore,
        printer,
        () => current,
        (_) async => 'ip',
      );
      addTearDown(guarded.dispose);
      final job = await guarded.enqueue(
        selected: selected,
        documentId: 'receipt:asset',
        reference: '1',
        payload: {
          'logoBytes': Uint8List.fromList([1, 2, 3]),
        },
      );
      assetStore.switchOnRead = true;
      expect((await guarded.send(job.id, selected)).status, PrintStatus.failed);
      expect(printer.sent, isEmpty);
    },
  );

  test('storage failure prevents any printer transmission', () async {
    final failing = PrintQueue(
      FailingStore(),
      printer,
      () => current,
      (_) async => 'ip',
    );
    addTearDown(failing.dispose);
    await expectLater(
      failing.enqueue(
        selected: selected,
        documentId: 'receipt:1',
        reference: '1',
        payload: {},
      ),
      throwsStateError,
    );
    expect(printer.connections, 0);
    expect(printer.sent, isEmpty);
  });
}

class FailingStore extends MemoryLocalStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Disk full');
}

class SwitchingAssetStore extends MemoryLocalStore {
  SwitchingAssetStore(this.changeScope);
  final void Function() changeScope;
  bool switchOnRead = false;
  @override
  Future<String?> read(String key) async {
    if (switchOnRead && key.startsWith('print-asset:')) changeScope();
    return super.read(key);
  }
}
