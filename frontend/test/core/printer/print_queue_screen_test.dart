import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/print_queue_providers.dart';
import 'package:top_coffee_pos/core/printer/print_queue_screen.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import '../../support/memory_local_store.dart';

void main() {
  testWidgets(
    'uncertain print offers a confirmed COPY action, not a blind retry',
    (tester) async {
      const scope = (userId: 16, branchId: 21);
      final queue = PrintQueue(
        MemoryLocalStore(),
        PrinterService(),
        () => scope,
        (_) async => 'ip',
      );
      addTearDown(queue.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final job = PrintJob(
        id: 'saved',
        userId: 16,
        branchId: 21,
        documentId: 'receipt:124',
        fingerprint: 'snapshot',
        reference: 'PP-01-000121',
        payload: {},
        createdAt: DateTime(2026, 10, 14),
        status: PrintStatus.uncertain,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            printScopeProvider.overrideWithValue(scope),
            printQueueProvider.overrideWithValue(queue),
            printJobsProvider.overrideWith((ref) => Stream.value([job])),
          ],
          child: const MaterialApp(home: PrintQueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check paper — confirmation unknown'), findsOneWidget);
      expect(find.text('0 failed · 1 need paper check · 0 waiting'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      final copy = find.widgetWithText(OutlinedButton, 'Reprint COPY');
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(find.text('Print a COPY?'), findsOneWidget);
      expect(
        find.textContaining('previous attempt may already have printed'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all branches requires selection instead of exposing jobs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printScopeProvider.overrideWithValue(null),
          printJobsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: PrintQueueScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Select a branch'), findsOneWidget);
    expect(find.text('Reprint COPY'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
