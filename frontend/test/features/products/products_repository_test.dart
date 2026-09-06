import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/products/data/products_repository.dart';
import 'package:top_coffee_pos/features/products/domain/managed_product_models.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockApiClient apiClient;
  late ApiProductsRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = ApiProductsRepository(apiClient);
  });

  test('getCategories parses the GET /api/v1/categories response', () async {
    final responseData = {
      'success': true,
      'data': [
        {'id': 1, 'branch_id': null, 'name': 'Coffee', 'sort_order': 1},
      ],
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/categories')),
    );

    final categories = await repository.getCategories();

    expect(categories, hasLength(1));
    expect(categories.single.name, 'Coffee');
  });

  test('getProducts parses the GET /api/v1/products response', () async {
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
      ],
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/products')),
    );

    final products = await repository.getProducts();

    expect(products, hasLength(1));
    expect(products.single.name, 'Iced Latte');
    expect(products.single.hasVariants, isTrue);
  });

  group('createProduct', () {
    test('POSTs to /products and parses the management response shape', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 20,
          'name': 'Latte',
          'sku': 'COF-LATTE',
          'description': null,
          'base_price': 3.50,
          'is_active': true,
          'category': {'id': 1, 'name': 'Coffee'},
          'variants': [],
          'branches': [],
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/products')),
      );

      const newProduct = ManagedProduct(name: 'Latte', categoryId: 1, basePrice: 3.50);
      final saved = await repository.createProduct(newProduct);

      expect(saved.id, 20);
      expect(saved.name, 'Latte');
      expect(saved.basePrice, 3.50);
    });

    // These two tests verify the actual mechanism of the "newly created
    // products are invisible" fix: GET /api/v1/products requires a
    // branch_product row to return a product at all (see
    // ProductController::index()), so createProduct() must include a
    // `branches` array whenever branchIds is non-empty, and must NOT send
    // one at all when it's empty (an empty array would still count as
    // "the branches key is present" server-side, which isn't the same as
    // "don't touch branches" — omitting the key entirely is what keeps
    // create() and update() consistent about that distinction).
    test('includes a branches array with is_available:true when branchIds is provided', () async {
      final mockDio = MockDio();
      when(() => mockDio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          data: {
            'success': true,
            'data': {
              'id': 21,
              'name': 'Latte',
              'sku': null,
              'description': null,
              'base_price': 3.50,
              'is_active': true,
              'category': {'id': 1, 'name': 'Coffee'},
              'variants': [],
              'branches': [],
            },
          },
          requestOptions: RequestOptions(path: '/products'),
        ),
      );

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer((invocation) async {
        final call = invocation.positionalArguments[0] as Future<Response<dynamic>> Function(Dio);
        return call(mockDio);
      });

      const newProduct = ManagedProduct(name: 'Latte', categoryId: 1, basePrice: 3.50);
      await repository.createProduct(newProduct, branchIds: [7]);

      final captured = verify(
        () => mockDio.post<dynamic>('/products', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;

      expect(sentData['branches'], [
        {'branch_id': 7, 'is_available': true},
      ]);
    });

    test('omits the branches key entirely when branchIds is not provided', () async {
      final mockDio = MockDio();
      when(() => mockDio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          data: {
            'success': true,
            'data': {
              'id': 22,
              'name': 'Latte',
              'sku': null,
              'description': null,
              'base_price': 3.50,
              'is_active': true,
              'category': null,
              'variants': [],
              'branches': [],
            },
          },
          requestOptions: RequestOptions(path: '/products'),
        ),
      );

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer((invocation) async {
        final call = invocation.positionalArguments[0] as Future<Response<dynamic>> Function(Dio);
        return call(mockDio);
      });

      const newProduct = ManagedProduct(name: 'Latte', categoryId: 1, basePrice: 3.50);
      await repository.createProduct(newProduct); // branchIds omitted entirely

      final captured = verify(
        () => mockDio.post<dynamic>('/products', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;

      expect(sentData.containsKey('branches'), isFalse);
    });
  });

  group('updateProduct', () {
    test('PATCHes to /products/{id} and parses the management response shape', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 20,
          'name': 'Iced Latte',
          'sku': 'COF-LATTE',
          'description': null,
          'base_price': 3.75,
          'is_active': true,
          'category': {'id': 1, 'name': 'Coffee'},
          'variants': [],
          'branches': [],
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/products/20')),
      );

      const updated = ManagedProduct(id: 20, name: 'Iced Latte', categoryId: 1, basePrice: 3.75);
      final saved = await repository.updateProduct(20, updated);

      expect(saved.name, 'Iced Latte');
      expect(saved.basePrice, 3.75);
    });
  });

  group('setProductActive', () {
    test('PATCHes /products/{id} with only is_active and completes without error', () async {
      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          data: {'success': true, 'data': {}},
          requestOptions: RequestOptions(path: '/products/20'),
        ),
      );

      await expectLater(repository.setProductActive(20, false), completes);
    });

    test('propagates an API error rather than swallowing it', () async {
      when(() => apiClient.request<Response<dynamic>>(any())).thenThrow(Exception('network down'));

      expect(() => repository.setProductActive(20, false), throwsException);
    });
  });
}
