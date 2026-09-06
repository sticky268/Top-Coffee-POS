import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/products/application/product_form_controller.dart';
import 'package:top_coffee_pos/features/products/application/product_form_state.dart';
import 'package:top_coffee_pos/features/products/data/products_repository.dart';
import 'package:top_coffee_pos/features/products/domain/managed_product_models.dart';

class MockProductsRepository extends Mock implements ProductsRepository {}

const _newProduct = ManagedProduct(
  name: 'Latte',
  categoryId: 1,
  basePrice: 3.50,
);

const _savedProduct = ManagedProduct(
  id: 20,
  name: 'Latte',
  categoryId: 1,
  basePrice: 3.50,
);

void main() {
  late MockProductsRepository repository;

  setUp(() {
    repository = MockProductsRepository();
  });

    ({ProviderContainer container, ProductFormController controller}) build() {
    final container = ProviderContainer(
      overrides: [
        productsRepositoryProvider.overrideWithValue(repository),
      ],
    );

    final subscription = container.listen<ProductFormState>(
      productFormControllerProvider,
      (_, __) {},
    );

    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final controller =
        container.read(productFormControllerProvider.notifier);

    return (container: container, controller: controller);
  }

  test('starts in ProductFormIdle', () {
    final built = build();

    expect(
      built.container.read(productFormControllerProvider),
      isA<ProductFormIdle>(),
    );
  });

  group('create', () {
    test('transitions Idle -> Saving -> Success', () async {
      when(
        () => repository.createProduct(
          _newProduct,
          branchIds: any(named: 'branchIds'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _savedProduct;
      });

      final built = build();
      final future = built.controller.create(_newProduct);

      expect(
        built.container.read(productFormControllerProvider),
        isA<ProductFormSaving>(),
      );

      await future;

      final state = built.container.read(productFormControllerProvider);

      expect(state, isA<ProductFormSuccess>());
      expect((state as ProductFormSuccess).product.id, 20);
    });

    test(
      'a second create() call while already saving is ignored (double-submit guard)',
      () async {
        when(
          () => repository.createProduct(
            _newProduct,
            branchIds: any(named: 'branchIds'),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _savedProduct;
        });

        final built = build();

        final first = built.controller.create(_newProduct);
        final second = built.controller.create(_newProduct);

        await first;
        await second;

        verify(
          () => repository.createProduct(
            _newProduct,
            branchIds: any(named: 'branchIds'),
          ),
        ).called(1);
      },
    );

    test(
      'a ValidationException surfaces its first field error as the message',
      () async {
        when(
          () => repository.createProduct(
            _newProduct,
            branchIds: any(named: 'branchIds'),
          ),
        ).thenThrow(
          const ValidationException({
            'sku': ['The sku has already been taken.'],
          }),
        );

        final built = build();

        await built.controller.create(_newProduct);

        final state = built.container.read(productFormControllerProvider);

        expect(state, isA<ProductFormError>());
        expect(
          (state as ProductFormError).message,
          'The sku has already been taken.',
        );
      },
    );

    test('a generic ApiException surfaces its own message', () async {
      when(
        () => repository.createProduct(
          _newProduct,
          branchIds: any(named: 'branchIds'),
        ),
      ).thenThrow(
        const UnknownApiException('Server error'),
      );

      final built = build();

      await built.controller.create(_newProduct);

      expect(
        (built.container.read(productFormControllerProvider)
                as ProductFormError)
            .message,
        'Server error',
      );
    });

    test(
      'does not throw when the container is disposed mid-save',
      () async {
        when(
          () => repository.createProduct(
            _newProduct,
            branchIds: any(named: 'branchIds'),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _savedProduct;
        });

        final container = ProviderContainer(
          overrides: [
            productsRepositoryProvider.overrideWithValue(repository),
          ],
        );

        final controller =
            container.read(productFormControllerProvider.notifier);

        final future = controller.create(_newProduct);

        container.dispose();

        await expectLater(future, completes);
      },
    );
  });

  group('update', () {
    test(
      'transitions Idle -> Saving -> Success and calls the repository with the given id',
      () async {
        when(
          () => repository.updateProduct(20, _savedProduct),
        ).thenAnswer((_) async => _savedProduct);

        final built = build();

        await built.controller.update(20, _savedProduct);

        final state = built.container.read(productFormControllerProvider);

        expect(state, isA<ProductFormSuccess>());

        verify(
          () => repository.updateProduct(20, _savedProduct),
        ).called(1);
      },
    );

    test('a repository failure results in ProductFormError', () async {
      when(
        () => repository.updateProduct(20, _savedProduct),
      ).thenThrow(
        Exception('down'),
      );

      final built = build();

      await built.controller.update(20, _savedProduct);

      expect(
        built.container.read(productFormControllerProvider),
        isA<ProductFormError>(),
      );
    });
  });
}
