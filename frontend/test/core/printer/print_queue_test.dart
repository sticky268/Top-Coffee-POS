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
