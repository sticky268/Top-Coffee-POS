import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/inventory/application/inventory_list_controller.dart';
import 'package:top_coffee_pos/features/inventory/data/ingredient_impact.dart';
import 'package:top_coffee_pos/features/inventory/presentation/ingredient_impact_panel.dart';

const _scope = (userId: 1, branchId: 2);
final _activeScope = StateProvider<InventoryScope?>((ref) => _scope);
const _first = IngredientImpactPage(products: [
  IngredientProductLink(id: 10, name: 'Latte'),
], nextAfterId: 10);

void main() {
  Future<ProviderContainer> pump(WidgetTester tester,
      Future<IngredientImpactPage> Function(IngredientImpactQuery) load) async {
    final container = ProviderContainer(overrides: [
      inventoryScopeProvider.overrideWith((ref) => ref.watch(_activeScope)),
      ingredientImpactProvider.overrideWith((ref, query) => load(query)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: IngredientImpactPanel(ingredientId: 4, scope: _scope),
      )))));
    return container;
  }

  testWidgets('collapsed rows make no request; expansion reads only the selected ingredient', (tester) async {
    final queries = <IngredientImpactQuery>[];
    await pump(tester, (query) async { queries.add(query); return _first; });
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    await tester.tap(find.text('Show products using this ingredient'));
    await tester.pumpAndSettle();
    expect(queries.single, (ingredientId: 4, scope: _scope, afterId: null));
    expect(find.text('• Latte'), findsOneWidget);
    expect(find.textContaining('optional modifiers'), findsOneWidget);
    expect(find.textContaining('do not determine'), findsOneWidget);
  });

  testWidgets('next and previous navigate bounded pages', (tester) async {
    await pump(tester, (query) async => query.afterId == null ? _first
        : const IngredientImpactPage(products: [
            IngredientProductLink(id: 20, name: 'Cappuccino')]));
    await tester.tap(find.text('Show products using this ingredient'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next products'));
    await tester.pumpAndSettle();
    expect(find.text('• Cappuccino'), findsOneWidget);
    expect(find.text('• Latte'), findsNothing);
    await tester.tap(find.text('Previous products'));
    await tester.pumpAndSettle();
    expect(find.text('• Latte'), findsOneWidget);
  });

  testWidgets('failure is not shown as an empty recipe and retry recovers', (tester) async {
    var calls = 0;
    await pump(tester, (query) async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return const IngredientImpactPage(products: []);
    });
    await tester.tap(find.text('Show products using this ingredient'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load recipe links'), findsOneWidget);
    expect(find.textContaining('No active products'), findsNothing);
    await tester.tap(find.text('Retry recipe links'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No active products'), findsOneWidget);
    expect(find.textContaining('Unrecorded recipes are not checked'), findsOneWidget);
  });

  testWidgets('branch change hides an in-flight response from the previous scope', (tester) async {
    final pending = Completer<IngredientImpactPage>();
    final container = await pump(tester, (query) => pending.future);
    await tester.tap(find.text('Show products using this ingredient'));
    await tester.pump();
    container.read(_activeScope.notifier).state = (userId: 1, branchId: 99);
    await tester.pump();
    pending.complete(_first);
    await tester.pumpAndSettle();
    expect(find.text('• Latte'), findsNothing);
    expect(find.text('Hide products using this ingredient'), findsNothing);
  });

  testWidgets('long product names wrap on a phone with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, (query) async => const IngredientImpactPage(products: [
      IngredientProductLink(id: 1,
        name: 'Extra long seasonal coffee name with optional milk and caramel'),
    ]));
    await tester.tap(find.text('Show products using this ingredient'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('oversized response is rejected instead of rendering unbounded names', () {
    expect(() => IngredientImpactPage.fromJson({
      'data': List.generate(21, (id) => {'id': id, 'name': 'Coffee'}),
      'meta': {'next_after_id': null},
    }), throwsA(isA<FormatException>()));
  });
}
