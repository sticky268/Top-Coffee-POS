import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/inventory/data/inventory_repository.dart';
import 'package:top_coffee_pos/features/inventory/domain/inventory_models.dart';
import 'package:top_coffee_pos/features/products/data/products_repository.dart';
import 'package:top_coffee_pos/features/products/domain/managed_product_models.dart';
import 'package:top_coffee_pos/features/products/presentation/recipe_editor_screen.dart';

class MockProductsRepository extends Mock implements ProductsRepository {}

class MockInventoryRepository extends Mock implements InventoryRepository {}

void main() {
  testWidgets('Coffee Bean quantity Cancel closes without framework exceptions',
      (tester) async {
    final products = MockProductsRepository();
    final inventory = MockInventoryRepository();
    when(() => products.getRecipe(productId: 1, branchId: 1))
        .thenAnswer((_) async => []);
    when(() => inventory.getIngredients(branchId: 1)).thenAnswer((_) async => [
          const InventoryIngredient(
            id: 1,
            name: 'Coffee Bean',
            unit: InventoryUnit(id: 1, name: 'Grams', abbreviation: 'g'),
            currentStock: 1000,
            reorderThreshold: 100,
            isLowStock: false,
            isActive: true,
          ),
        ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsRepositoryProvider.overrideWithValue(products),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          currentBranchProvider.overrideWith((ref) {
            return CurrentBranchNotifier(ref, listenToAuth: false)
              ..selectBranch(
                const BranchSummary(id: 1, name: 'Test branch', code: 'TEST'),
              );
          }),
        ],
        child: const MaterialApp(
          home: RecipeEditorScreen(
            product: ManagedProduct(
              id: 1,
              name: 'Espresso',
              categoryId: 1,
              basePrice: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No ingredients added yet.'), findsOneWidget);

    // Repeat the flow to catch controller reuse after the first cancellation.
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Add Ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coffee Bean'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      // showDialog completes before its route finishes the exit animation.
      // Exercise both the first closing frame and the remaining teardown.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('No ingredients added yet.'), findsOneWidget);
      expect(find.text('Coffee Bean'), findsNothing);
    }

    verify(() => products.getRecipe(productId: 1, branchId: 1)).called(1);
    verify(() => inventory.getIngredients(branchId: 1)).called(2);
    // Cancellation must not persist or otherwise change the recipe.
    verifyNoMoreInteractions(products);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
