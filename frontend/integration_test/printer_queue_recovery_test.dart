import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/core/storage/app_database.dart';

class RehearsalPrinter extends PrinterService {
  bool offline = true;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> connect(String ip) async {
    if (offline) throw StateError('Simulated disconnected printer');
  }

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    sent.add(payload);
  }

  @override
  Future<void> disconnect() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SQLite print jobs survive reopen without duplicate or uncertain replay',
    (tester) async {
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Printer queue recovery rehearsal')),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final root = await getTemporaryDirectory();
        final directory = await Directory(
          root.path,
        ).createTemp('printer-queue-rehearsal-');
        final file = File('${directory.path}/jobs.sqlite');
        const scope = (userId: 999997, branchId: 999997);
        final printer = RehearsalPrinter();
        var database = AppDatabase.forTesting(NativeDatabase(file));
        var store = SqliteLocalStore(database);
        PrintQueue makeQueue() =>
            PrintQueue(store, printer, () => scope, (_) async => 'rehearsal');
        var queue = makeQueue();
        try {
          final original = await queue.enqueue(
            selected: scope,
            documentId: 'receipt:fixture',
            reference: 'FIXTURE-000001',
            payload: {
              'logoBytes': Uint8List.fromList([1, 2, 3]),
              'total': '5.00',
              'documentTitle': '',
              'items': [
                {'name': 'កាហ្វេ', 'quantity': 1},
              ],
            },
          );
          expect(
            (await queue.send(original.id, scope)).status,
            PrintStatus.failed,
          );
          queue.dispose();
          await database.close();
          database = AppDatabase.forTesting(NativeDatabase(file));
          store = SqliteLocalStore(database);
          queue = makeQueue();
          await queue.resumeWaiting(scope);
          expect(printer.sent, isEmpty);
          printer.offline = false;
          expect(
            (await queue.send(original.id, scope)).status,
            PrintStatus.sent,
          );
          await queue.send(original.id, scope);
          expect(printer.sent, hasLength(1));
          expect(printer.sent.single['logoBytes'], [1, 2, 3]);
          expect((await store.entries('print-asset:')).length, 1);
          expect(
            (printer.sent.single['items'] as List).single['name'],
            'កាហ្វេ',
          );
          await store.write('literal_%:one', 'first');
          await store.write('literalX%:two', 'second');
          expect(await store.entries('literal_%:'), {'literal_%:one': 'first'});
          final interrupted = await queue.enqueue(
            selected: scope,
            documentId: 'receipt:interrupted',
            reference: 'FIXTURE-000002',
            payload: {'total': '7.00', 'documentTitle': ''},
          );
          await store.write(
            'print:${scope.userId}:${scope.branchId}:${interrupted.id}',
            // Simulate the durable marker left by a killed app during sending.
            jsonEncode(
              interrupted.change({
                'status': PrintStatus.sending.name,
                'attempts': 1,
              }).toJson(),
            ),
          );
          queue.dispose();
          await database.close();
          database = AppDatabase.forTesting(NativeDatabase(file));
          store = SqliteLocalStore(database);
          queue = makeQueue();
          await queue.resumeWaiting(scope);
          expect(
            (await queue.list(
              scope,
            )).singleWhere((j) => j.id == interrupted.id).status,
            PrintStatus.uncertain,
          );
          expect(printer.sent, hasLength(1));
          final copy = await queue.copy(interrupted.id, scope);
          await queue.send(copy.id, scope);
          expect(printer.sent, hasLength(2));
          expect(printer.sent.last['documentTitle'], 'COPY');
          debugPrint(
            'PASS: Native SQLite print recovery, Khmer snapshot, no duplicate replay and COPY label. No real printer or API mutation.',
          );
        } finally {
          queue.dispose();
          await database.close();
          await directory.delete(recursive: true);
        }
      });
    },
  );
  testWidgets('native Android receipt reaches a simulated TCP printer intact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Loopback is deliberate: this test cannot contact a shop printer.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 9100);
      final received = BytesBuilder(copy: false);
      final finished = Completer<void>();
      Socket? peer;
      var connections = 0;
      final accepting = server.listen((socket) {
        connections++;
        peer = socket;
        socket.listen(
          received.add,
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!finished.isCompleted) finished.completeError(error, stack);
          },
        );
      });
      final printer = PrinterService();
      try {
        await printer.connect('127.0.0.1');
        await printer.sendPayload({
          'businessName': 'SYNTHETIC PRINTER TEST',
          'documentTitle': 'COPY - TEST ONLY',
          'branchName': 'Emulator loopback',
          'orderNumber': 'FIXTURE-ONLY',
          'cashierName': 'Automated test',
          'orderType': 'takeaway',
          'subtotal': '140.00',
          'discount': '0.00',
          'total': '140.00',
          'paymentMethod': 'cash',
          'tendered': '150.00',
          'changeDue': '10.00',
          'footer': 'END OF SYNTHETIC RECEIPT',
          'items': List.generate(40, (index) => {
            'name': 'Coffee ${index + 1} កាហ្វេ',
            'quantity': 1,
            'unitPrice': '3.50',
            'lineTotal': '3.50',
          }),
        });
        await printer.disconnect();
        await finished.future.timeout(const Duration(seconds: 10));
        expect(connections, 1);
        final bytes = received.takeBytes();
        expect(bytes.take(2), [27, 64]);
        var cursor = 2;
        var rows = 0;
        var bands = 0;
        var cuts = 0;
        final ink = <int>[];
        while (cursor < bytes.length) {
          if (bytes[cursor] == 27 &&
              cursor + 3 <= bytes.length &&
              bytes[cursor + 1] == 97 && bytes[cursor + 2] == 0) {
            cursor += 3; // SDK alignment before/after each raster band.
          } else if (bytes[cursor] == 29 &&
              cursor + 8 <= bytes.length &&
              bytes[cursor + 1] == 118 && bytes[cursor + 2] == 48) {
            expect(bytes[cursor + 3], 0);
            final width = bytes[cursor + 4] + 256 * bytes[cursor + 5];
            final height = bytes[cursor + 6] + 256 * bytes[cursor + 7];
            expect(width, 72, reason: 'Receipt must retain its 576-dot width');
            expect(height, inInclusiveRange(1, 24));
            final end = cursor + 8 + width * height;
            expect(end, lessThanOrEqualTo(bytes.length),
                reason: 'Truncated raster payload');
            ink.add(bytes.sublist(cursor + 8, end).where((b) => b != 0).length);
            rows += height;
            bands++;
            cursor = end;
          } else if (bytes[cursor] == 29 &&
              cursor + 4 <= bytes.length &&
              bytes[cursor + 1] == 86 && bytes[cursor + 2] == 66 &&
              bytes[cursor + 3] == 1) {
            cursor += 4;
            cuts++;
            expect(cursor, bytes.length, reason: 'Cut must be the final command');
          } else {
            fail('Unexpected or corrupt ESC/POS command at byte $cursor');
          }
        }
        expect(rows, greaterThan(1600));
        expect(bands, greaterThan(66));
        expect(cuts, 1);
        expect(ink.take(ink.length ~/ 2).any((count) => count > 0), isTrue);
        expect(ink.skip(ink.length ~/ 2).any((count) => count > 0), isTrue);
        debugPrint('PASS: native Android receipt: ${bytes.length} bytes, '
            '$rows rows, $bands intact raster bands, one final cut; '
            'no shop printer, payment or drawer command.');
      } finally {
        await printer.disconnect();
        peer?.destroy();
        await accepting.cancel();
        await server.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

}
