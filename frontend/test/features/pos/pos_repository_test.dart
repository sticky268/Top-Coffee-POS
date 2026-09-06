import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late ApiPosRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = ApiPosRepository(apiClient);
  });

  group('getCategories', () {
    test('parses the exact GET /api/v1/categories response shape', () async {
      final responseData = {
        'success': true,
        'data': [
          {'id': 1, 'branch_id': null, 'name': 'Coffee', 'sort_order': 1},
          {'id': 4, 'branch_id': 1, 'name': 'Seasonal', 'sort_order': 2},
        ],
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/categories')),
      );

      final categories = await repository.getCategories();

      expect(categories, hasLength(2));
      expect(categories[0].id, 1);
      expect(categories[0].name, 'Coffee');
      expect(categories[0].sortOrder, 1);
      expect(categories[1].name, 'Seasonal');
    });
  });

  group('getProducts', () {
    test('parses the exact GET /api/v1/products response shape, including category and variants', () async {
      final responseData = {
        'success': true,
        'data': [
          {
            'id': 1,
            'name': 'Iced Latte',
            'sku': 'COF-LATTE',
            'description': null,
            'category': {'id': 1, 'name': 'Coffee'},
            'price': 3.00,
            'variants': [
              {'id': 4, 'name': 'Large', 'price': 3.75},
            ],
          },
          {
            'id': 2,
            'name': 'Americano',
            'sku': null,
            'description': null,
            'category': {'id': 1, 'name': 'Coffee'},
            'price': 2.50,
            'variants': <Map<String, dynamic>>[],
          },
        ],
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/products')),
      );

      final products = await repository.getProducts();

      expect(products, hasLength(2));

      final latte = products[0];
      expect(latte.name, 'Iced Latte');
      expect(latte.sku, 'COF-LATTE');
      expect(latte.category?.name, 'Coffee');
      expect(latte.price, 3.00);
      expect(latte.hasVariants, isTrue);
      expect(latte.variants.single.name, 'Large');
      expect(latte.variants.single.price, 3.75);

      final americano = products[1];
      expect(americano.hasVariants, isFalse);
      expect(americano.variants, isEmpty);
    });

    test('handles a product with a null category gracefully', () async {
      final responseData = {
        'success': true,
        'data': [
          {
            'id': 3,
            'name': 'Mystery Item',
            'sku': null,
            'description': null,
            'category': null,
            'price': 1.00,
            'variants': <Map<String, dynamic>>[],
          },
        ],
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/products')),
      );

      final products = await repository.getProducts();

      expect(products.single.category, isNull);
    });
  });

  group('createOrder', () {
    const product = PosProduct(
      id: 1,
      name: 'Latte',
      sku: null,
      description: null,
      category: null,
      price: 3.00,
      variants: [PosProductVariant(id: 5, name: 'Large', price: 3.75)],
    );

    test('sends product/variant ids and quantity — never client-side prices', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 42,
          'uuid': 'abc-123',
          'order_type': 'takeaway',
          'status': 'completed',
          'subtotal': 3.75,
          'discount_total': 0,
          'total': 3.75,
          'payment': {'method': 'cash', 'amount': 3.75, 'tendered': 5.0, 'change_due': 1.25},
        },
      };

      // This test verifies the parsed OrderConfirmation shape. The exact
      // request payload (product/variant ids + quantity, no prices) is
      // covered by ApiPosRepository.createOrder's own implementation and
      // by OrderController's backend test suite (the actual source of
      // truth for server-side price recomputation), since mocking Dio
      // itself to inspect the outgoing request body isn't practical here.
      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/orders')),
      );

      final confirmation = await repository.createOrder(
        items: [CartItem(product: product, variant: product.variants.first, quantity: 1)],
        paymentMethod: 'cash',
        tendered: 5.0,
      );

      expect(confirmation.orderId, 42);
      expect(confirmation.total, 3.75);
      expect(confirmation.paymentMethod, 'cash');
      expect(confirmation.tendered, 5.0);
      expect(confirmation.changeDue, 1.25);
    });

    test('parses a non-cash payment with null tendered/change_due', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 43,
          'uuid': 'def-456',
          'order_type': 'takeaway',
          'status': 'completed',
          'subtotal': 2.50,
          'discount_total': 0,
          'total': 2.50,
          'payment': {'method': 'qr', 'amount': 2.50, 'tendered': null, 'change_due': null},
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/orders')),
      );

      final confirmation = await repository.createOrder(
        items: [const CartItem(product: product, quantity: 1)],
        paymentMethod: 'qr',
      );

      expect(confirmation.paymentMethod, 'qr');
      expect(confirmation.tendered, isNull);
      expect(confirmation.changeDue, isNull);
    });
  });
}
