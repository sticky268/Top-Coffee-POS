import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/open_order_screen.dart';

class MockPosRepository extends Mock implements PosRepository {}

class MockOrdersRepository extends Mock implements OrdersRepository {}

OrderDetail bill({int quantity = 1, double unitPrice = 3.50}) => OrderDetail(
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

  setUp(() {
    pos = MockPosRepository();
    orders = MockOrdersRepository();
    saved = bill(quantity: 2, unitPrice: 4);
    var reads = 0;
    when(() => orders.getOrder(42))
        .thenAnswer((_) async => reads++ == 0 ? bill() : saved);
    when(() => pos.getCategories()).thenAnswer((_) async => []);
    when(() => pos.getProducts()).thenAnswer((_) async => []);
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

  Future<void> pumpBill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/bill',
      routes: [
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posRepositoryProvider.overrideWithValue(pos),
          ordersRepositoryProvider.overrideWithValue(orders),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Pay saves edited quantities and confirms the server price', (
    tester,
  ) async {
    await pumpBill(tester);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    final items =
        verify(
              () => pos.updateHeldOrder(
                orderId: 42,
                items: captureAny(named: 'items'),
                discountTotal: 0,
                branchId: 11,
              ),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(items.single['quantity'], 2);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('\$8.00'),
      ),
      findsOneWidget,
    );
    verifyNever(
      () => pos.payHeldOrder(
        orderId: any(named: 'orderId'),
        paymentMethod: any(named: 'paymentMethod'),
        expectedTotal: any(named: 'expectedTotal'),
        branchId: any(named: 'branchId'),
      ),
    );

    await tester.tap(find.text('Confirm Payment'));
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
    expect(find.text('Tables'), findsOneWidget);
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
    await tester.tap(find.text('Pay'));
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
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
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

  testWidgets('repeated Pay taps cannot start another save', (tester) async {
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
      find.widgetWithText(FilledButton, 'Pay'),
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
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
