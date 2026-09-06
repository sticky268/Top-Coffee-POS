import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/products/application/products_controller.dart';
import 'package:top_coffee_pos/features/products/application/products_state.dart';
import 'package:top_coffee_pos/features/products/data/products_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

class MockProductsRepository extends Mock implements ProductsRepository {}

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
  late MockProductsRepository repository;

  setUp(() {
    repository = MockProductsRepository();
  });

  ({ProviderContainer container, ProductsController controller}) buildAndStart() {
    final container = ProviderContainer(
      overrides: [productsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(productsControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  test('loads successfully into ProductsLoaded', () async {
    when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(productsControllerProvider);
    expect(state, isA<ProductsLoaded>());
    expect((state as ProductsLoaded).products, hasLength(2));
  });

  test('a repository failure results in ProductsError, never a stuck Loading', () async {
    when(() => repository.getCategories()).thenThrow(Exception('network down'));
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

    final built = buildAndStart();
    await built.controller.initialization;

    final state = built.container.read(productsControllerProvider);
    expect(state, isNot(isA<ProductsLoading>()));
    expect(state, isA<ProductsError>());
  });

  test('refresh() can recover from a prior error', () async {
    when(() => repository.getCategories()).thenThrow(Exception('down'));
    when(() => repository.getProducts()).thenAnswer((_) async => [_latte]);

    final built = buildAndStart();
    await built.controller.initialization;
    expect(built.container.read(productsControllerProvider), isA<ProductsError>());

    when(() => repository.getCategories()).thenAnswer((_) async => [_coffee]);
    await built.controller.refresh();

    expect(built.container.read(productsControllerProvider), isA<ProductsLoaded>());
  });

  group('filtering', () {
    test('selectCategory filters locally without a second API call', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.selectCategory(1); // Coffee

      final loaded = built.container.read(productsControllerProvider) as ProductsLoaded;
      expect(loaded.visibleProducts, hasLength(1));
      expect(loaded.visibleProducts.single.name, 'Latte');
      expect(loaded.isFiltered, isTrue);
      verify(() => repository.getProducts()).called(1);
    });

    test('updateSearchQuery filters by name, case-insensitively', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      built.controller.updateSearchQuery('GREEN');

      final loaded = built.container.read(productsControllerProvider) as ProductsLoaded;
      expect(loaded.visibleProducts, hasLength(1));
      expect(loaded.visibleProducts.single.name, 'Green Tea');
    });

    test('with no filter applied, isFiltered is false and every product is visible', () async {
      when(() => repository.getCategories()).thenAnswer((_) async => [_coffee, _tea]);
      when(() => repository.getProducts()).thenAnswer((_) async => [_latte, _greenTea]);

      final built = buildAndStart();
      await built.controller.initialization;

      final loaded = built.container.read(productsControllerProvider) as ProductsLoaded;
      expect(loaded.isFiltered, isFalse);
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
      overrides: [productsRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(productsControllerProvider.notifier);

    container.dispose();

    await expectLater(controller.initialization, completes);
  });
}
