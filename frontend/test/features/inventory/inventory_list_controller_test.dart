import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/inventory/application/inventory_list_controller.dart';
import 'package:top_coffee_pos/features/inventory/data/inventory_repository.dart';
import 'package:top_coffee_pos/features/inventory/domain/inventory_models.dart';

class _Repository extends Mock implements InventoryRepository {}
class _Auth extends Mock implements AuthRepository {}
final _selectedScope = StateProvider<InventoryScope?>((ref) =>
    (userId: 1, branchId: 1));

InventoryIngredient _item(int id) => InventoryIngredient(
  id: id, name: 'Branch $id',
  unit: const InventoryUnit(id: 1, name: 'Unit', abbreviation: 'u'),
  currentStock: 5, reorderThreshold: 1, isLowStock: false, isActive: true,
);

void main() {
  late _Repository repository;
  setUp(() { repository = _Repository(); });
  ProviderContainer container() {
    final container = ProviderContainer(overrides: [
      inventoryRepositoryProvider.overrideWithValue(repository),
      inventoryScopeProvider.overrideWith((ref) => ref.watch(_selectedScope)),
    ]);
    addTearDown(container.dispose);
    container.listen(inventoryListControllerProvider, (previous, next) {});
    return container;
  }
  test('loads selected branch explicitly and refreshes it', () async {
    when(() => repository.getIngredients(branchId: 1))
        .thenAnswer((_) async => [_item(1)]);
    final c = container();
    expect((await c.read(inventoryListControllerProvider.future)).ingredients.single.id, 1);
    await c.read(inventoryListControllerProvider.notifier).refresh();
    verify(() => repository.getIngredients(branchId: 1)).called(2);
    verifyNever(() => repository.getIngredients());
  });
  test('late response from previous branch cannot replace current inventory', () async {
    final old = Completer<List<InventoryIngredient>>();
    when(() => repository.getIngredients(branchId: 1)).thenAnswer((_) => old.future);
    when(() => repository.getIngredients(branchId: 2)).thenAnswer((_) async => [_item(2)]);
    final c = container();
    c.read(inventoryListControllerProvider.future);
    c.read(_selectedScope.notifier).state = (userId: 1, branchId: 2);
    final current = await c.read(inventoryListControllerProvider.future);
    expect(current.ingredients.single.id, 2);
    expect(current.scope, (userId: 1, branchId: 2));
    old.complete([_item(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(inventoryListControllerProvider).requireValue.ingredients.single.id, 2);
  });
  test('loss of account scope removes old stock and makes no unscoped query', () async {
    when(() => repository.getIngredients(branchId: 1))
        .thenAnswer((_) async => [_item(1)]);
    final c = container();
    await c.read(inventoryListControllerProvider.future);
    c.read(_selectedScope.notifier).state = null;
    await expectLater(c.read(inventoryListControllerProvider.future),
        throwsA(isA<StateError>()));
    expect(c.read(inventoryListControllerProvider).hasError, isTrue);
    verifyNever(() => repository.getIngredients());
  });
  test('scope rejects unassigned branch and missing inventory permission', () async {
    const first = BranchSummary(id: 1, name: 'One', code: 'ONE');
    const other = BranchSummary(id: 2, name: 'Two', code: 'TWO');
    final auth = _Auth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => const AuthenticatedUser(
      id: 7, name: 'Manager', email: 'manager@example.test',
      roles: ['manager'], permissions: ['inventory.view'], branches: [first],
    ));
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      currentBranchProvider.overrideWith((ref) =>
          CurrentBranchNotifier(ref, listenToAuth: false)..selectBranch(first)),
    ]);
    addTearDown(c.dispose);
    await c.read(authControllerProvider.notifier).initialization;
    expect(c.read(inventoryScopeProvider), (userId: 7, branchId: 1));
    c.read(currentBranchProvider.notifier).selectBranch(other);
    expect(c.read(inventoryScopeProvider), isNull);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => const AuthenticatedUser(
      id: 7, name: 'Manager', email: 'manager@example.test',
      roles: ['manager'], permissions: [], branches: [first],
    ));
    c.read(currentBranchProvider.notifier).selectBranch(first);
    await c.read(authControllerProvider.notifier).restoreSession();
    expect(c.read(inventoryScopeProvider), isNull);
  });
}
