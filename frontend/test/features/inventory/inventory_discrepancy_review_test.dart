import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/inventory/data/inventory_repository.dart';
import 'package:top_coffee_pos/features/inventory/domain/inventory_models.dart';
import 'package:top_coffee_pos/features/inventory/presentation/inventory_movement_history_screen.dart';

class _Repository extends Mock implements InventoryRepository {}

void main() {
  const ingredient = InventoryIngredient(
    id: 17,
    name: 'Milk',
    unit: InventoryUnit(id: 1, name: 'Gram', abbreviation: 'g'),
    currentStock: 3,
    reorderThreshold: 1,
    isLowStock: false,
    isActive: true,
  );

  testWidgets('linked stock discrepancy loads only the original ledger entry',
      (tester) async {
    final repository = _Repository();
    when(() => repository.getStockMovements(
      ingredientId: 17,
      movementId: 42,
      page: 1,
      perPage: 20,
    )).thenAnswer((_) async => [
      InventoryStockMovement(
        id: 42,
        ingredientId: 17,
        type: 'adjustment',
        quantity: -2,
        balanceAfter: 3,
        reason: 'Stock count: counted again',
        createdAt: DateTime.utc(2026, 10, 15),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: InventoryMovementHistoryScreen(
        ingredient: ingredient, initialMovementId: 42,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Stock count discrepancy'), findsOneWidget);
    expect(find.textContaining('Recorded before: 5.000 g'), findsOneWidget);
    expect(find.textContaining('Counted: 3.000 g'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    verify(() => repository.getStockMovements(
      ingredientId: 17,
      movementId: 42,
      page: 1,
      perPage: 20,
    )).called(1);
  });

  testWidgets('missing linked movement reports absence, never a different row',
      (tester) async {
    final repository = _Repository();
    when(() => repository.getStockMovements(
      ingredientId: 17,
      movementId: 43,
      page: 1,
      perPage: 20,
    )).thenAnswer((_) async => []);
    await tester.pumpWidget(ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: InventoryMovementHistoryScreen(
        ingredient: ingredient, initialMovementId: 43,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected stock count was not found'), findsOneWidget);
  });
}
