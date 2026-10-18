import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';
import 'package:top_coffee_pos/features/orders/domain/orders_list_filters.dart';
import 'package:top_coffee_pos/features/orders/presentation/orders_screen.dart';
import 'package:top_coffee_pos/features/orders/presentation/widgets/order_list_tile.dart';

class _Orders extends Mock implements OrdersRepository {}

OrderSummary order(int id) => OrderSummary(
      id: id,
      orderNumber: id,
      uuid: 'fixture-$id',
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 5,
      discountTotal: 0,
      total: 5,
      branch: null,
      cashier: null,
      payment: null,
      createdAt: null,
    );

void main() {
  testWidgets('orders filters scroll away while pagination and refresh work',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Orders();
    var firstPageReads = 0;
    when(() => repo.getOrders(
        page: 1,
        branchId: null,
        filters: OrdersListFilters.empty)).thenAnswer((_) async {
      firstPageReads++;
      return OrderListPage(
          orders: List.generate(8, (i) => order(i + 1)),
          currentPage: 1,
          lastPage: 2,
          total: 9);
    });
    when(() => repo.getOrders(
            page: 2, branchId: null, filters: OrdersListFilters.empty))
        .thenAnswer((_) async => OrderListPage(
            orders: [order(9)], currentPage: 2, lastPage: 2, total: 9));
    await tester.pumpWidget(ProviderScope(
        overrides: [ordersRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: OrdersScreen())));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.byType(OrderListTile).hitTestable(), findsWidgets);
    verify(() => repo.getOrders(
        page: 2, branchId: null, filters: OrdersListFilters.empty)).called(1);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(firstPageReads, 2);
    // Refresh may retain the reading position; search remains reachable above.
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
