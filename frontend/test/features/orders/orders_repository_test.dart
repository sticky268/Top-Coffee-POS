import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockApiClient apiClient;
  late ApiOrdersRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = ApiOrdersRepository(apiClient);
  });

  group('getOrders', () {
    test('parses the exact GET /api/v1/orders response shape, including meta', () async {
      final responseData = {
        'success': true,
        'data': [
          {
            'id': 42,
            'uuid': 'abc-123',
            'order_type': 'takeaway',
            'status': 'completed',
            'subtotal': 10.0,
            'discount_total': 0,
            'total': 10.0,
            'branch': {'id': 1, 'name': 'Riverside', 'code': 'PP-01'},
            'cashier': {'id': 3, 'name': 'Cashier User'},
            'payment': {'method': 'cash', 'status': 'completed'},
            'created_at': '2026-08-31T09:15:00+00:00',
          },
        ],
        'meta': {'current_page': 1, 'last_page': 3, 'per_page': 20, 'total': 45},
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/orders')),
      );

      final page = await repository.getOrders();

      expect(page.orders, hasLength(1));
      expect(page.orders.single.id, 42);
      expect(page.orders.single.branch?.name, 'Riverside');
      expect(page.orders.single.cashier?.name, 'Cashier User');
      expect(page.orders.single.payment?.method, 'cash');
      expect(page.currentPage, 1);
      expect(page.lastPage, 3);
      expect(page.total, 45);
      expect(page.hasMore, isTrue);
    });

    test('handles null branch/cashier/payment gracefully', () async {
      final responseData = {
        'success': true,
        'data': [
          {
            'id': 7,
            'uuid': 'def-456',
            'order_type': 'takeaway',
            'status': 'completed',
            'subtotal': 5.0,
            'discount_total': 0,
            'total': 5.0,
            'branch': null,
            'cashier': null,
            'payment': null,
            'created_at': null,
          },
        ],
        'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 1},
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/orders')),
      );

      final page = await repository.getOrders();

      expect(page.orders.single.branch, isNull);
      expect(page.orders.single.cashier, isNull);
      expect(page.orders.single.payment, isNull);
      expect(page.orders.single.createdAt, isNull);
      expect(page.hasMore, isFalse);
    });
  });

  group('getOrder', () {
    test('parses the exact GET /api/v1/orders/{id} response shape, including items', () async {
      final responseData = {
        'success': true,
        'data': {
          'id': 42,
          'uuid': 'abc-123',
          'order_type': 'takeaway',
          'status': 'completed',
          'subtotal': 10.0,
          'discount_total': 1.0,
          'total': 9.0,
          'branch': {'id': 1, 'name': 'Riverside', 'code': 'PP-01'},
          'cashier': {'id': 3, 'name': 'Cashier User'},
          'table': {
            'id': 5,
            'name': 'T5',
            'capacity': 4,
            'status': 'occupied',
          },
          'items': [
            {
              'id': 1,
              'product_id': 1,
              'product_name': 'Latte',
              'variant_name': 'Large',
              'quantity': 2,
              'unit_price': 3.75,
              'line_total': 7.50,
            },
            {
              'id': 2,
              'product_id': 2,
              'product_name': 'Americano',
              'variant_name': null,
              'quantity': 1,
              'unit_price': 2.50,
              'line_total': 2.50,
            },
          ],
          'payment': {
            'method': 'cash',
            'status': 'completed',
            'amount': 9.0,
            'tendered': 10.0,
            'change_due': 1.0,
          },
          'payments': [
            {
              'id': 1,
              'method': 'cash',
              'status': 'completed',
              'amount': 9.0,
              'tendered': 10.0,
              'change_due': 1.0,
            },
          ],
          'created_at': '2026-08-31T09:15:00+00:00',
        },
      };

      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(data: responseData, requestOptions: RequestOptions(path: '/orders/42')),
      );

      final order = await repository.getOrder(42);

      expect(order.id, 42);
      expect(order.items, hasLength(2));
      expect(order.items[0].productName, 'Latte');
      expect(order.items[0].variantName, 'Large');
      expect(order.items[1].variantName, isNull);
      expect(order.table?.name, 'T5');
      expect(order.table?.capacity, 4);
      expect(order.payments, hasLength(1));
      expect(order.payments.single.method, 'cash');
      expect(order.payments.single.amount, 9.0);
      expect(order.payment?.tendered, 10.0);
      expect(order.payment?.changeDue, 1.0);
      expect(order.discountTotal, 1.0);
    });

    test('a missing/inaccessible order surfaces as an ApiException (404)', () async {
      when(() => apiClient.request<Response<dynamic>>(any()))
          .thenThrow(const UnknownApiException('Order not found'));

      expect(() => repository.getOrder(999999), throwsA(isA<UnknownApiException>()));
    });
  });

  group('branch_id threading (branch switcher support)', () {
    test('getOrders sends branch_id as a query parameter when provided', () async {
      final mockDio = MockDio();
      when(() => mockDio.get<dynamic>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
        (_) async => Response(
          data: {
            'success': true,
            'data': <Map<String, dynamic>>[],
            'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 0},
          },
          requestOptions: RequestOptions(path: '/orders'),
        ),
      );
      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer((invocation) async {
        final call = invocation.positionalArguments[0] as Future<Response<dynamic>> Function(Dio);
        return call(mockDio);
      });

      await repository.getOrders(branchId: 2);

      final captured = verify(
        () => mockDio.get<dynamic>('/orders', queryParameters: captureAny(named: 'queryParameters')),
      ).captured;
      final params = captured.single as Map;
      expect(params['branch_id'], 2);
      expect(params['page'], 1); // existing pagination param untouched
    });

    test('getOrders omits branch_id entirely when not provided', () async {
      final mockDio = MockDio();
      when(() => mockDio.get<dynamic>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
        (_) async => Response(
          data: {
            'success': true,
            'data': <Map<String, dynamic>>[],
            'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 0},
          },
          requestOptions: RequestOptions(path: '/orders'),
        ),
      );
      when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer((invocation) async {
        final call = invocation.positionalArguments[0] as Future<Response<dynamic>> Function(Dio);
        return call(mockDio);
      });

      await repository.getOrders();

      final captured = verify(
        () => mockDio.get<dynamic>('/orders', queryParameters: captureAny(named: 'queryParameters')),
      ).captured;
      expect((captured.single as Map).containsKey('branch_id'), isFalse);
    });
  });
}
