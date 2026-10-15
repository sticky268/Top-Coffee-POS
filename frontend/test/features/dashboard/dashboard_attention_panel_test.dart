import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/print_queue_providers.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_attention_panel.dart';

class _Auth extends Mock implements AuthRepository {}
const _branch = BranchSummary(id: 2, name: 'Riverside', code: 'RIV');
PendingOrder _order(String status) => PendingOrder(
  uuid: status, userId: 1, branchId: 2, endpoint: '/orders', payload: const {},
  createdAt: DateTime.utc(2026, 10, 15), fingerprint: status, status: status,
);
PrintJob _job(PrintStatus status) => PrintJob(
  id: status.name, userId: 1, branchId: 2, documentId: 'order-1',
  fingerprint: status.name, reference: 'Order 1', payload: const {},
  createdAt: DateTime.utc(2026, 10, 15), status: status,
);

void main() {
  Future<void> pumpPanel(WidgetTester tester, {
    List<String> permissions = const ['orders.view', 'inventory.view'],
    List<PendingOrder> orders = const [],
    List<PrintJob> jobs = const [],
    bool queueError = false,
    BranchSummary branch = _branch,
    int cashDiscrepancies = 0,
  }) async {
    final auth = _Auth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => AuthenticatedUser(
      id: 1, name: 'Manager', email: 'manager@example.test', roles: const ['manager'],
      permissions: permissions, branches: const [_branch],
    ));
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      currentBranchProvider.overrideWith((ref) =>
          CurrentBranchNotifier(ref, listenToAuth: false)..selectBranch(branch)),
      pendingOrdersProvider.overrideWith((ref) => queueError
          ? Stream.error(StateError('unavailable')) : Stream.value(orders)),
      printJobsProvider.overrideWith((ref) => queueError
          ? Stream.error(StateError('unavailable')) : Stream.value(jobs)),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).initialization;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(
        body: SingleChildScrollView(child: DashboardAttentionPanel(lowStockCount: 3,
          cashDiscrepancyCount: cashDiscrepancies,
          cashDiscrepancyShiftId: cashDiscrepancies > 0 ? 41 : null)),
      )),
      GoRoute(path: '/pending-orders', builder: (context, state) =>
        const Scaffold(body: Text('Saved order review destination'))),
      GoRoute(path: '/print-queue', builder: (context, state) =>
        const Scaffold(body: Text('Receipt review destination'))),
      GoRoute(path: '/operations', builder: (context, state) =>
        Scaffold(body: Text('Shift review: ${state.uri.queryParameters['shift_id']}'))),
      GoRoute(path: '/inventory', builder: (context, state) =>
        Scaffold(body: Text('Inventory filter: ${state.uri.queryParameters['filter']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
  }

  testWidgets('shows real scoped queue exceptions and opens saved order review', (tester) async {
    await pumpPanel(tester,
      orders: [_order('pending'), _order('review'), _order('synced')],
      jobs: [_job(PrintStatus.uncertain), _job(PrintStatus.sent)]);
    expect(find.text('1 saved order needs review'), findsOneWidget);
    expect(find.text('1 receipt needs attention'), findsOneWidget);
    expect(find.textContaining('this account on this device'), findsOneWidget);
    await tester.tap(find.text('1 saved order needs review'));
    await tester.pumpAndSettle();
    expect(find.text('Saved order review destination'), findsOneWidget);
  });
  testWidgets('stock attention opens the restock filter directly', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('3 ingredients need restocking'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory filter: low-stock'), findsOneWidget);
  });
  testWidgets('print exception opens existing receipt recovery', (tester) async {
    await pumpPanel(tester, jobs: [_job(PrintStatus.failed)]);
    await tester.tap(find.text('1 receipt needs attention'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt review destination'), findsOneWidget);
  });
  testWidgets('manager cash alert links to the exact unreviewed shift', (tester) async {
    await pumpPanel(tester,
      permissions: const ['reports.view'], cashDiscrepancies: 2);
    expect(find.text('2 shifts have an unreviewed cash difference'), findsOneWidget);
    await tester.tap(find.text('2 shifts have an unreviewed cash difference'));
    await tester.pumpAndSettle();
    expect(find.text('Shift review: 41'), findsOneWidget);
  });

  testWidgets('cash discrepancy alert is hidden without report permission', (tester) async {
    await pumpPanel(tester,
      permissions: const ['orders.view'], cashDiscrepancies: 2);
    expect(find.textContaining('unreviewed cash difference'), findsNothing);
  });

  testWidgets('unavailable queues are explicit and do not claim confirmation', (tester) async {
    await pumpPanel(tester, queueError: true);
    expect(find.text('Saved order status unavailable'), findsOneWidget);
    expect(find.text('Receipt status unavailable'), findsOneWidget);
    expect(find.textContaining('No confirmation is assumed'), findsOneWidget);
  });
  testWidgets('permission and branch guards hide inaccessible actions', (tester) async {
    await pumpPanel(tester, permissions: const ['reports.view']);
    expect(find.text('Needs attention'), findsNothing);
    await pumpPanel(tester, branch: const BranchSummary(
      id: 99, name: 'Other branch', code: 'OTHER'),
      orders: [_order('review')], jobs: [_job(PrintStatus.failed)]);
    expect(find.text('Needs attention'), findsNothing);
  });
  testWidgets('attention cards wrap at phone width and large text', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPanel(tester, orders: [_order('review')], jobs: [_job(PrintStatus.uncertain)]);
    expect(tester.takeException(), isNull);
  });
}
