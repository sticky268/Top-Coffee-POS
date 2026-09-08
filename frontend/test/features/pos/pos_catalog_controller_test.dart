import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_controller.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_state.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

class MockPosRepository extends Mock implements PosRepository {}

const _coffee = PosCategory(id: 1, name: 'Coffee', sortOrder: 1);
const _tea = PosCategory(id: 2, name: 'Tea', sortOrder: 2);

const _latte = PosProduct(
  id: 1,
  name: 'Latte',
  sku: null,
  description: null,
  category: PosProductCategoryRef(id: 1, name: 'Coffee'),
  price: 3.50,
  variants: [],
);

const _greenTea = PosProduct(
  id: 2,
  name: 'Green Tea',
  sku: null,
  description: null,
  category: PosProductCategoryRef(id: 2, name: 'Tea'),
  price: 2.50,
  variants: [],
);

void main() {
  late MockPosRepository repository;

  setUp(() {
    repository = MockPosRepository();
  });

  /// Same pattern established for AuthController/DashboardController:
  /// reading `.notifier` forces the lazy provider to construct
  /// immediately, and `initialization` is a deterministic completion
  /// signal — no guessing with delays.
  ({ProviderContainer container, PosCatalogController controller}) buildAndStart() {
    final container = ProviderContainer(
      overrides: [posRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(posCatalogControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  test('loads successfully into PosCatalogLoaded with categories and products', () async {
    when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(posCatalogControllerProvider);
    expect(state, isA<PosCatalogLoaded>());
    final loaded = state as PosCatalogLoaded;
    expect(loaded.categories, hasLength(2));
    expect(loaded.products, hasLength(2));
    expect(loaded.selectedCategoryId, isNull); // "All" by default
  });

  test('a repository failure results in PosCatalogError, never a stuck Loading', () async {
    when(() => repository.getCategories()).thenThrow(Exception('network down'));
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(posCatalogControllerProvider);
    expect(state, isNot(isA<PosCatalogLoading>()));
    expect(state, isA<PosCatalogError>());
  });

  test('refresh() can recover from a prior error', () async {
    when(() => repository.getCategories()).thenThrow(Exception('network down'));
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

    final built = buildAndStart();
    await built.controller.initialization;
    expect(built.container.read(posCatalogControllerProvider), isA<PosCatalogError>());

    when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
    await built.controller.refresh();

    expect(built.container.read(posCatalogControllerProvider), isA<PosCatalogLoaded>());
  });

    test('reloads catalog when the current branch changes', () async {
    const branch74 = BranchSummary(
      id: 74,
      name: 'Top Coffee - Riverside',
      code: 'PP-01',
    );

    const branch75 = BranchSummary(
      id: 75,
      name: 'Top Coffee - BKK1',
      code: 'PP-02',
    );

    when(() => repository.getCategories(branchId: 74))
        .thenAnswer((_) async => [_coffee]);

    when(() => repository.getProducts(branchId: 74))
        .thenAnswer((_) async => [_latte]);

    when(() => repository.getCategories(branchId: 75))
        .thenAnswer((_) async => [_tea]);

    when(() => repository.getProducts(branchId: 75))
        .thenAnswer((_) async => [_greenTea]);

    final built = buildAndStart();
    await built.controller.initialization;

    built.container
        .read(currentBranchProvider.notifier)
        .selectBranch(branch74);

    await built.controller.initialization;

    var loaded =
        built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;

    expect(loaded.products.single.name, 'Latte');

    built.container
        .read(currentBranchProvider.notifier)
        .selectBranch(branch75);

    await built.controller.initialization;

    loaded =
        built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;

    expect(loaded.products.single.name, 'Green Tea');

    verify(() => repository.getProducts(branchId: 74)).called(1);
    verify(() => repository.getProducts(branchId: 75)).called(1);
  });

  group('selectCategory + visibleProducts', () {
    test('"All" (null) shows every product', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      final loaded = built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;
      expect(loaded.visibleProducts, hasLength(2));
    });

    test('selecting a category filters products locally, without a new API call', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.selectCategory(1); // Coffee

      final loaded = built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;
      expect(loaded.visibleProducts, hasLength(1));
      expect(loaded.visibleProducts.single.name, 'Latte');

      // getProducts() must have been called exactly once — the initial
      // load — never again just from selecting a category tab.
      verify(() => repository.getProducts()).called(1);
    });

    test('selectCategory is a no-op while the catalog is still loading', () async {
      when(() => repository.getCategories()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return [_coffee];
      });
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

      final built = buildAndStart();
      // Deliberately not awaiting initialization here — still Loading.
      built.controller.selectCategory(1);

      expect(built.container.read(posCatalogControllerProvider), isA<PosCatalogLoading>());

      await built.controller.initialization; // let it finish for teardown safety
    });

    test('updateSearchQuery filters products by name, case-insensitively', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.updateSearchQuery('lat');

      final loaded = built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;
      expect(loaded.visibleProducts, hasLength(1));
      expect(loaded.visibleProducts.single.name, 'Latte');
      verify(() => repository.getProducts()).called(1); // no new API call per keystroke
    });

    test('category selection and search query combine (both must match)', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.selectCategory(2); // Tea
      built.controller.updateSearchQuery('latte'); // matches nothing in Tea

      final loaded = built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;
      expect(loaded.visibleProducts, isEmpty);
      expect(loaded.selectedCategoryId, 2); // selection preserved by updateSearchQuery
    });

    test('clearing the search query restores the category-filtered list', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.updateSearchQuery('green');
      built.controller.updateSearchQuery('');

      final loaded = built.container.read(posCatalogControllerProvider) as PosCatalogLoaded;
      expect(loaded.visibleProducts, hasLength(2));
    });
  });

  test('does not throw when the container is disposed mid-load', () async {
    when(() => repository.getCategories()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return [_coffee];
    });
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

    final container = ProviderContainer(
      overrides: [posRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(posCatalogControllerProvider.notifier);

    container.dispose();

    await expectLater(controller.initialization, completes);
  });
}
