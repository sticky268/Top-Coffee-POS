import 'dart:convert';
import 'dart:io';

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
          expect(
            (printer.sent.single['items'] as List).single['name'],
            'កាហ្វេ',
          );
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
}
