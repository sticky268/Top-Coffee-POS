import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/checkout_screen.dart';
import 'package:top_coffee_pos/features/pos/presentation/select_table_screen.dart';

class MockPos extends Mock implements PosRepository {}

void main() {
  testWidgets(
      'switching checkout to dine-in selects a table and preserves items',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockPos();
    const table = PosTable(
        id: 7,
        name: 'T7',
        capacity: 4,
        status: 'available',
        activeOrderId: null);
    when(() => repo.getTables(branchId: null)).thenAnswer((_) async => [table]);
    final cart = CartController();
    cart.addItem(const PosProduct(
        id: 1,
        name: 'Latte',
        sku: null,
        description: null,
        category: null,
        price: 3.5,
        variants: []));
    final router = GoRouter(initialLocation: '/checkout', routes: [
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
          path: '/pos/select-table',
          builder: (_, __) => const SelectTableScreen(selectionOnly: true)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      posRepositoryProvider.overrideWithValue(repo),
      cartControllerProvider.overrideWith((_) => cart),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dine-in'));
    await tester.pumpAndSettle();
    expect(find.text('Select Table'), findsOneWidget);
    await tester.tap(find.text('T7'));
    await tester.pumpAndSettle();
    expect(find.text('Change T7'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CheckoutScreen)));
    expect(container.read(cartControllerProvider).items.single.quantity, 1);
    expect(container.read(cartControllerProvider).table?.id, 7);
    await tester.scrollUntilVisible(find.text('Save Order'), 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
    await tester.pumpAndSettle();
    expect(find.text('Save Order').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
