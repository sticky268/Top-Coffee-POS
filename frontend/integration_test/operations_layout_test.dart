import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/dashboard_screen.dart';
import 'package:top_coffee_pos/features/operations/presentation/operations_screen.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_card.dart';

import 'operations_readonly_smoke_test.dart' as smoke;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rehearsal screens fit phone and tablet viewports', (
    tester,
  ) async {
    expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
    runApp(
      ProviderScope(
        overrides: [orderSyncWorkerProvider.overrideWith((ref) {})],
        child: const TopCoffeeApp(),
      ),
    );
    await smoke.waitForHome(tester);
    final context = tester.element(find.byType(DashboardScreen));
    final container = ProviderScope.containerOf(context);
    final router = GoRouter.of(context);
    expect(
      container.read(cartControllerProvider).items,
      isEmpty,
      reason: 'Refusing to change a pre-existing cart.',
    );
    addTearDown(() async {
      container.read(cartControllerProvider.notifier).clear();
      await binding.setSurfaceSize(null);
    });
    for (final size in [
      const Size(360, 800),
      const Size(800, 1280),
      const Size(1280, 800),
    ]) {
      await binding.setSurfaceSize(size);
      router.go('/home');
      await tester.pump();
      await smoke.waitForControl(tester, find.byType(DashboardScreen));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Dashboard must render at ${size.width} x ${size.height}.',
      );
      router.go('/operations');
      await tester.pump();
      await smoke.waitForOperations(tester);
      for (final section in [
        'Shifts',
        'Stock counts',
        'Availability',
        'Owner report',
      ]) {
        final chip = find.widgetWithText(ChoiceChip, section);
        if (chip.evaluate().isEmpty) continue;
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await smoke.waitForOperations(tester);
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        expect(
          tester.takeException(),
          isNull,
          reason: '$section must fit ${size.width} x ${size.height}.',
        );
      }
      router.go('/pos');
      await tester.pump();
      await smoke.waitForControl(tester, find.byType(GridView));
      final card = find.byWidgetPredicate(
        (w) => w is ProductCard && w.product.id == 6,
      );
      await tester.scrollUntilVisible(
        card,
        250,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final product = tester.widget<ProductCard>(card).product;
      await tester.tap(card);
      if (product.hasVariants) {
        final option = find.widgetWithText(
          ListTile,
          product.variants.first.name,
        );
        await smoke.waitForControl(tester, option);
        await tester.tap(option);
      }
      await tester.pumpAndSettle();
      final review = find.text('Review Order').last;
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      expect(
        review.hitTestable(),
        findsOneWidget,
        reason: 'Cart checkout action must be reachable.',
      );
      await tester.tap(review.hitTestable());
      await smoke.waitForControl(tester, find.text('Takeaway order'));
      final amount = find.widgetWithText(TextField, 'Amount received');
      await tester.scrollUntilVisible(
        amount,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        amount,
        container.read(cartControllerProvider).total.toStringAsFixed(2),
      );
      await tester.pumpAndSettle();
      final pay = find.text('Confirm & Pay');
      await tester.scrollUntilVisible(
        pay,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        pay.hitTestable(),
        findsOneWidget,
        reason: 'Payment action must fit the viewport.',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Cart and checkout must fit ${size.width} x ${size.height}.',
      );
      // Inspect checkout only: never submit payment or hold an order.
      router.go('/home');
      container.read(cartControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
      debugPrint(
        'PASS: Dashboard, operations, POS cart and checkout fit ${size.width.toInt()} x ${size.height.toInt()}; no sale submitted.',
      );
    }
    expect(find.byType(OperationsScreen), findsNothing);
  });
}
