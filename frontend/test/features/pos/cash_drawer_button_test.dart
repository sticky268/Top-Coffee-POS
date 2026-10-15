import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/print_queue_providers.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/cash_drawer_button.dart';
import '../../support/memory_local_store.dart';

class _Auth extends Mock implements AuthRepository {}
class _Printer extends PrinterService {
  final connected = Completer<void>();
  int pulses = 0;
  bool fail = false;
  @override
  Future<void> connect(String ip) => connected.future;
  @override
  Future<void> openCashDrawer() async {
    pulses++;
    if (fail) throw StateError('Printer unavailable');
  }
  @override
  Future<void> disconnect() async {}
}

void main() {
  late PrintQueue lastQueue;
  Future<void> request(WidgetTester tester) async {
    await tester.tap(find.text('Open cash drawer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Make change');
    await tester.tap(find.text('Open drawer'));
    await tester.pump();
  }
  Future<_Printer> pump(WidgetTester tester, {bool allowed = true, bool enabled = true, bool compact = false, bool managerControls = false}) async {
    SharedPreferences.setMockInitialValues({'receipt_printer_enabled_branch_test': enabled});
    final auth = _Auth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => AuthenticatedUser(
      id: 1, name: 'Cashier', email: 'cashier@example.test',
      requireManagerControls: managerControls,
      roles: ['cashier'], permissions: allowed ? ['orders.create'] : ['orders.view'],
      branches: [const BranchSummary(id: 2, name: 'Test', code: 'TEST')],
    ));
    final printer = _Printer();
    final queue = PrintQueue(MemoryLocalStore(), printer,
      () => (userId: 1, branchId: 2), (_) async => 'ip');
    lastQueue = queue;
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      printQueueProvider.overrideWithValue(queue),
    ]);
    addTearDown(container.dispose);
    addTearDown(queue.dispose);
    await container.read(authControllerProvider.notifier).initialization;
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(
        builder: compact ? (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 160),
          ),
          child: child!,
        ) : null,
        home: const Scaffold(body: CashDrawerButton()),
      )));
    await tester.pump();
    return printer;
  }

  testWidgets('cashier can send one manual command despite repeated taps', (tester) async {
    final printer = await pump(tester);
    await request(tester);
    expect(find.text('Sending…'), findsOneWidget);
    await tester.tap(find.text('Sending…'));
    expect(printer.pulses, 0);
    printer.connected.complete();
    await tester.pumpAndSettle();
    expect(printer.pulses, 1);
    final event = (await lastQueue.drawerJournal.list((userId: 1, branchId: 2))).single;
    expect(event.reason, 'Make change');
    expect(event.status, 'command_sent');
    expect(find.text('Drawer command sent. Check the drawer.'), findsOneWidget);
  });

  testWidgets('manager controls hide manual drawer access from a cashier', (tester) async {
    final printer = await pump(tester, managerControls: true);
    expect(find.text('Open cash drawer'), findsNothing);
    expect(printer.pulses, 0);
  });

  testWidgets('view-only staff have no drawer action', (tester) async {
    await pump(tester, allowed: false);
    expect(find.text('Open cash drawer'), findsNothing);
  });

  testWidgets('disabled branch printer sends no pulse and explains the failure', (tester) async {
    final printer = await pump(tester, enabled: false);
    await request(tester);
    await tester.pumpAndSettle();
    expect(printer.pulses, 0);
    expect(find.textContaining('Enable this branch'), findsOneWidget);
  });

  testWidgets('printer failure is visible and not automatically retried', (tester) async {
    final printer = await pump(tester);
    printer.fail = true;
    printer.connected.complete();
    await request(tester);
    await tester.pumpAndSettle();
    expect(printer.pulses, 1);
    expect(find.textContaining('Could not confirm drawer command.'), findsOneWidget);
  });
  testWidgets('cancelled or blank reasons never send a drawer command', (tester) async {
    final printer = await pump(tester);
    await tester.tap(find.text('Open cash drawer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason with at least 3 characters.'), findsOneWidget);
    expect(printer.pulses, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await lastQueue.drawerJournal.list((userId: 1, branchId: 2)), isEmpty);
  });

  testWidgets('reason and confirmation remain reachable on a short phone with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final printer = await pump(tester, compact: true);
    await tester.tap(find.text('Open cash drawer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'Make change');
    await tester.ensureVisible(find.text('Open drawer'));
    await tester.tap(find.text('Open drawer'));
    await tester.pump();
    printer.connected.complete();
    await tester.pumpAndSettle();
    expect(printer.pulses, 1);
    expect(tester.takeException(), isNull);
  });

}
