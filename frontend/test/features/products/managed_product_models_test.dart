import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/products/domain/managed_product_models.dart';

void main() {
  group('ManagedProduct.fromJson', () {
    test('parses the exact ProductController::present() response shape', () {
      final json = {
        'id': 1,
        'name': 'Latte',
        'sku': 'COF-LATTE',
        'description': 'A coffee drink',
        'base_price': 3.50,
        'is_active': true,
        'category': {'id': 2, 'name': 'Coffee'},
        'variants': [
          {'id': 5, 'name': 'Large', 'sku': null, 'price_delta': 0.75, 'is_active': true},
        ],
        'branches': [],
      };

      final product = ManagedProduct.fromJson(json);

      expect(product.id, 1);
      expect(product.name, 'Latte');
      expect(product.categoryId, 2);
      expect(product.category?.name, 'Coffee');
      expect(product.basePrice, 3.50);
      expect(product.isActive, isTrue);
      expect(product.variants, hasLength(1));
      expect(product.variants.single.priceDelta, 0.75);
    });
  });

  group('ManagedProduct.toJson', () {
    test('always includes every field explicitly, nulling empty optionals rather than omitting them', () {
      const product = ManagedProduct(
        name: 'Latte',
        sku: '',
        description: '  ',
        categoryId: 2,
        basePrice: 3.50,
        isActive: false,
        variants: [],
      );

      final json = product.toJson();

      expect(json['name'], 'Latte');
      expect(json['category_id'], 2);
      expect(json['sku'], isNull); // empty string normalized to null
      expect(json['description'], isNull); // whitespace-only normalized to null
      expect(json['base_price'], 3.50);
      expect(json['is_active'], isFalse);
      expect(json['variants'], isEmpty);
      expect(json.containsKey('id'), isFalse); // id is never sent in the body
    });

    test('does not omit an unchanged sku/description', () {
      const product = ManagedProduct(
        name: 'Latte',
        sku: 'COF-LATTE',
        description: 'Rich and bold',
        categoryId: 2,
        basePrice: 3.50,
      );

      final json = product.toJson();

      expect(json['sku'], 'COF-LATTE');
      expect(json['description'], 'Rich and bold');
    });
  });

  group('ManagedProductVariant.toJson', () {
    test('includes id only when the variant already exists', () {
      const existing = ManagedProductVariant(id: 5, name: 'Large', priceDelta: 0.75);
      const brandNew = ManagedProductVariant(name: 'Small', priceDelta: -0.25);

      expect(existing.toJson()['id'], 5);
      expect(brandNew.toJson().containsKey('id'), isFalse);
    });
  });

  group('ManagedProduct.fromPosProduct', () {
    test('reconstructs a best-effort management shape from the catalog list item', () {
      const catalogProduct = PosProduct(
        id: 10,
        name: 'Iced Latte',
        sku: 'COF-LATTE',
        description: null,
        category: PosProductCategoryRef(id: 2, name: 'Coffee'),
        price: 3.00, // branch-resolved price
        variants: [
          PosProductVariant(id: 7, name: 'Large', price: 3.75), // absolute resolved price
        ],
      );

      final managed = ManagedProduct.fromPosProduct(catalogProduct);

      expect(managed.id, 10);
      expect(managed.categoryId, 2);
      // Documented approximation: catalog's resolved price stands in for
      // base_price (exact when no branch override is active).
      expect(managed.basePrice, 3.00);
      expect(managed.isActive, isTrue); // catalog list only ever has active products
      expect(managed.variants.single.id, 7);
      // Documented approximation: delta derived as resolved - base.
      expect(managed.variants.single.priceDelta, 0.75);
    });

    test('handles a product with no category', () {
      const catalogProduct = PosProduct(
        id: 11,
        name: 'Mystery Item',
        sku: null,
        description: null,
        category: null,
        price: 1.00,
        variants: [],
      );

      final managed = ManagedProduct.fromPosProduct(catalogProduct);

      expect(managed.category, isNull);
      expect(managed.categoryId, 0);
    });
  });
}
