import 'dart:async';
import 'package:top_coffee_pos/core/receipt/receipt_action_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';
import 'package:top_coffee_pos/features/orders/domain/orders_list_filters.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/open_order_screen.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';

class MockReceiptService extends Mock implements ReceiptActionService {}

class MockBillAuth extends Mock implements AuthRepository {}

class MockPosRepository extends Mock implements PosRepository {}

class MockOrdersRepository extends Mock implements OrdersRepository {}

OrderDetail bill(
        {int quantity = 1, double unitPrice = 3.50, String? revision}) =>
    OrderDetail(
      editRevision: revision,
      id: 42,
      uuid: 'held-42',
      orderType: 'dine_in',
      status: 'held',
      subtotal: quantity * unitPrice,
      discountTotal: 0,
      total: quantity * unitPrice,
      branch: const OrderBranchRef(id: 11, name: 'Riverside', code: 'PP-01'),
      cashier: null,
      table: const OrderTableRef(
        id: 1,
        name: 'T1',
        capacity: 4,
        status: 'occupied',
      ),
      items: [
        OrderLineItem(
          id: 1,
          productId: 1,
          productName: 'Latte',
          quantity: quantity,
          unitPrice: unitPrice,
          lineTotal: quantity * unitPrice,
        ),
      ],
      payment: null,
      createdAt: null,
    );

void main() {
  late MockPosRepository pos;
  late MockOrdersRepository orders;
  late OrderDetail saved;
  late MockReceiptService receipts;

  setUp(() {
    receipts = MockReceiptService();
    when(() => receipts.printReceipt(42, asCopy: false)).thenAnswer(
      (_) async => const OrderReceipt(
        orderId: 42,
        uuid: 'paid-42',
        orderType: 'dine_in',
        status: 'completed',
        subtotal: 8,
        discountTotal: 0,
        total: 8,
        items: [],
      ),
    );
    pos = MockPosRepository();
    orders = MockOrdersRepository();
    saved = bill(quantity: 2, unitPrice: 4);
    var reads = 0;
    when(() => orders.getOrder(42))
        .thenAnswer((_) async => reads++ == 0 ? bill() : saved);
    when(() => pos.getCategories()).thenAnswer((_) async => []);
    when(() => pos.getProducts()).thenAnswer((_) async => []);
    when(() => orders.getOrders(
          page: 1,
          branchId: null,
          filters: OrdersListFilters.empty,
        )).thenAnswer((_) async => const OrderListPage(
          orders: [],
          currentPage: 1,
          lastPage: 1,
          total: 0,
        ));
    when(
      () => pos.updateHeldOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11,
      ),
    ).thenAnswer(
      (_) async =>
          const OrderConfirmation(orderId: 42, total: 8, paymentMethod: ''),
    );
    when(
      () => pos.payHeldOrder(
        orderId: 42,
        paymentMethod: 'cash',
        tendered: null,
        expectedTotal: 8,
        branchId: 11,
      ),
    ).thenAnswer(
      (_) async =>
          const OrderConfirmation(orderId: 42, total: 8, paymentMethod: 'cash'),
    );
  });

  Future<void> pumpBill(
    WidgetTester tester, {
    List<String>? allowedMethods,
    bool fromList = false,
    Size viewport = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: fromList ? '/' : '/bill',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/bill'),
              child: const Text('Open Bill'),
            ),
          ),
        ),
        GoRoute(
          path: '/bill',
          builder: (_, __) => const OpenOrderScreen(orderId: 42),
        ),
        GoRoute(
          path: '/pos/select-table',
          builder: (_, __) => const Scaffold(body: Text('Tables')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final auth = MockBillAuth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => AuthenticatedUser(
          id: 1,
          name: 'Cashier',
          email: 'cashier@example.invalid',
          roles: const ['cashier'],
          permissions: const ['orders.create', 'orders.view'],
          branches: const [],
          allowedPaymentMethods: allowedMethods ?? const ['cash'],
        ));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posRepositoryProvider.overrideWithValue(pos),
          receiptActionServiceProvider.overrideWithValue(receipts),
          ordersRepositoryProvider.overrideWithValue(orders),
          if (allowedMethods != null)
            authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    if (fromList) {
      await tester.tap(find.text('Open Bill'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'Save returns to the list and reopening retains edited quantities',
      (tester) async {
    await pumpBill(tester, fromList: true);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Open Bill'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsNothing);

    final items = verify(() => pos.updateHeldOrder(
          orderId: 42,
          items: captureAny(named: 'items'),
          discountTotal: 0,
          branchId: 11,
        )).captured.single as List<Map<String, dynamic>>;
    expect(items.single['quantity'], 2);
    await tester.tap(find.text('Open Bill'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('\$8.00'), findsWidgets);
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsOneWidget);
  });

  testWidgets('Back warns about edits and Keep Editing preserves quantities',
      (tester) async {
    await pumpBill(tester, fromList: true);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes before leaving?'), findsOneWidget);
    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open Bill'), findsOneWidget);
    verifyNever(() => pos.updateHeldOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11));
  });

  testWidgets('phone exposes Save Order without opening the editor',
      (tester) async {
    await pumpBill(tester, fromList: true, viewport: const Size(390, 700));
    expect(find.text('Save Order').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save Order'));
    await tester.pumpAndSettle();
    expect(find.text('Open Bill'), findsOneWidget);
  });

  testWidgets('Pay saves edited quantities and confirms the server price', (
    tester,
  ) async {
    await pumpBill(tester);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    final items = verify(
      () => pos.updateHeldOrder(
        orderId: 42,
        items: captureAny(named: 'items'),
        discountTotal: 0,
        branchId: 11,
      ),
    ).captured.single as List<Map<String, dynamic>>;
    expect(items.single['quantity'], 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('\$8.00'), findsWidgets);
    expect(find.text('Print Bill'), findsOneWidget);
    expect(find.text('E-Bill'), findsOneWidget);
    verifyNever(
      () => pos.payHeldOrder(
        orderId: any(named: 'orderId'),
        paymentMethod: any(named: 'paymentMethod'),
        expectedTotal: any(named: 'expectedTotal'),
        branchId: any(named: 'branchId'),
      ),
    );

    await tester.tap(find.text('Complete Sale'));
    await tester.pumpAndSettle();
    verify(
      () => pos.payHeldOrder(
        orderId: 42,
        paymentMethod: 'cash',
        tendered: null,
        expectedTotal: 8,
        branchId: 11,
      ),
    ).called(1);
    expect(find.text('Payment Successful'), findsWidgets);
    expect(find.text('Print Receipt'), findsOneWidget);
    expect(find.text('E-Receipt'), findsOneWidget);

    await tester.tap(find.text('New Order'));
    await tester.pumpAndSettle();

    expect(find.text('Tables'), findsOneWidget);
  });

  testWidgets(
      'held payment only offers enabled methods and splits exact cash correctly',
      (tester) async {
    when(() =>
        pos.payHeldOrder(
            orderId: 42,
            paymentMethod: 'split',
            splitPayments: any(named: 'splitPayments'),
            expectedTotal: 8,
            branchId: 11)).thenAnswer((_) async =>
        const OrderConfirmation(orderId: 42, total: 8, paymentMethod: 'split'));
    await pumpBill(tester, allowedMethods: ['cash', 'card']);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    expect(find.text('QR'), findsNothing);
    await tester.ensureVisible(find.text('Split'));
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    final amount = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'First payment amount');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete Sale'));
    await tester.pumpAndSettle();
    final portions = verify(() => pos.payHeldOrder(
        orderId: 42,
        paymentMethod: 'split',
        splitPayments: captureAny(named: 'splitPayments'),
        expectedTotal: 8,
        branchId: 11)).captured.single;
    expect(portions, [
      {'method': 'cash', 'amount': 3.0, 'tendered': 3.0},
      {'method': 'card', 'amount': 5.0}
    ]);
    expect(find.text('Payment Successful'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash-only held order does not offer disabled payment methods',
      (tester) async {
    await pumpBill(tester, allowedMethods: ['cash']);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Card'), findsNothing);
    expect(find.text('QR'), findsNothing);
    expect(find.text('Split'), findsNothing);
    expect(find.text('Exact'), findsOneWidget);
  });

  testWidgets('held edits send the revision that was originally opened',
      (tester) async {
    when(() => orders.getOrder(42))
        .thenAnswer((_) async => bill(revision: 'revision-one'));
    when(() =>
        pos.updateHeldOrder(
            expectedRevision: 'revision-one',
            orderId: 42,
            items: any(named: 'items'),
            discountTotal: 0,
            branchId: 11)).thenAnswer((_) async =>
        const OrderConfirmation(orderId: 42, total: 3.5, paymentMethod: ''));
    await pumpBill(tester, fromList: true);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => pos.updateHeldOrder(
        expectedRevision: 'revision-one',
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11)).called(1);
  });

  testWidgets('a failed save never opens payment', (tester) async {
    when(
      () => pos.updateHeldOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11,
      ),
    ).thenThrow(Exception('Unavailable product'));
    await pumpBill(tester);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Payment was not started'), findsOneWidget);
    verifyNever(
      () => pos.payHeldOrder(
        orderId: any(named: 'orderId'),
        paymentMethod: any(named: 'paymentMethod'),
        expectedTotal: any(named: 'expectedTotal'),
        branchId: any(named: 'branchId'),
      ),
    );
  });

  testWidgets('cancelling payment keeps the saved bill without paying', (
    tester,
  ) async {
    await pumpBill(tester);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('\$8.00'), findsWidgets);
    verifyNever(
      () => pos.payHeldOrder(
        orderId: any(named: 'orderId'),
        paymentMethod: any(named: 'paymentMethod'),
        expectedTotal: any(named: 'expectedTotal'),
        branchId: any(named: 'branchId'),
      ),
    );
  });

  testWidgets('repeated Review & Pay taps cannot start another save',
      (tester) async {
    final pending = Completer<OrderConfirmation>();
    when(
      () => pos.updateHeldOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11,
      ),
    ).thenAnswer((_) => pending.future);
    await pumpBill(tester);
    final pay = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Review & Pay'),
    );
    pay.onPressed!();
    pay.onPressed!();
    await tester.pump();
    verify(
      () => pos.updateHeldOrder(
        orderId: 42,
        items: any(named: 'items'),
        discountTotal: 0,
        branchId: 11,
      ),
    ).called(1);
    pending.complete(
      const OrderConfirmation(orderId: 42, total: 8, paymentMethod: ''),
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
  testWidgets('phone keeps order actions visible without vertical overflow',
      (tester) async {
    await pumpBill(tester, viewport: const Size(360, 640));
    expect(find.text('View / Edit'), findsOneWidget);
    expect(find.text('Review & Pay').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('View / Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Order Summary'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone editor changes held quantities and saves without paying',
      (tester) async {
    await pumpBill(
      tester,
      fromList: true,
      viewport: const Size(390, 700),
    );
    await tester.tap(find.text('View / Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Open Bill'), findsOneWidget);
    final items = verify(() => pos.updateHeldOrder(
          orderId: 42,
          items: captureAny(named: 'items'),
          discountTotal: 0,
          branchId: 11,
        )).captured.single as List<Map<String, dynamic>>;
    expect(items.single['quantity'], 2);
    verifyNever(() => pos.payHeldOrder(
          orderId: any(named: 'orderId'),
          paymentMethod: any(named: 'paymentMethod'),
          expectedTotal: any(named: 'expectedTotal'),
          branchId: any(named: 'branchId'),
        ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone Review & Pay keeps the authoritative save-before-payment',
      (tester) async {
    await pumpBill(tester, viewport: const Size(390, 700));
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Review Order'), findsOneWidget);
    verify(() => pos.updateHeldOrder(
          orderId: 42,
          items: any(named: 'items'),
          discountTotal: 0,
          branchId: 11,
        )).called(1);
    verifyNever(() => pos.payHeldOrder(
          orderId: any(named: 'orderId'),
          paymentMethod: any(named: 'paymentMethod'),
          expectedTotal: any(named: 'expectedTotal'),
          branchId: any(named: 'branchId'),
        ));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Complete & Print prints once after payment succeeds',
      (tester) async {
    await pumpBill(tester);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete & Print'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Payment Successful'), findsWidgets);
    verify(() => receipts.printReceipt(42, asCopy: false)).called(1);
    await tester.pump();
    verifyNever(() => receipts.printReceipt(42, asCopy: false));
  });

  testWidgets('pending payment blocks repeated completion and back navigation',
      (tester) async {
    final pending = Completer<OrderConfirmation>();
    when(() => pos.payHeldOrder(
          orderId: 42,
          paymentMethod: 'cash',
          tendered: null,
          expectedTotal: 8,
          branchId: 11,
        )).thenAnswer((_) => pending.future);
    await pumpBill(tester);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Complete Sale'));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    verify(() => pos.payHeldOrder(
          orderId: 42,
          paymentMethod: 'cash',
          tendered: null,
          expectedTotal: 8,
          branchId: 11,
        )).called(1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Review Order'), findsOneWidget);
    pending.complete(
        const OrderConfirmation(orderId: 42, total: 8, paymentMethod: 'cash'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Successful'), findsWidgets);
    verifyNever(() => receipts.printReceipt(42, asCopy: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment failure stays on checkout without printing',
      (tester) async {
    when(() => pos.payHeldOrder(
          orderId: 42,
          paymentMethod: 'cash',
          tendered: null,
          expectedTotal: 8,
          branchId: 11,
        )).thenThrow(Exception('Network unavailable'));
    await pumpBill(tester);
    await tester.tap(find.text('Review & Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete & Print'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not complete payment'), findsOneWidget);
    expect(find.text('Review Order'), findsOneWidget);
    expect(find.text('Payment Successful'), findsNothing);
    verifyNever(() => receipts.printReceipt(42, asCopy: false));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Review & Pay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
