import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/customers/data/customers_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> customerJson({
  int id = 5,
  String name = 'John Doe',
}) =>
    {
      'id': id,
      'branch_id': 1,
      'name': name,
      'phone': '012345678',
      'email': 'john@example.com',
      'notes': 'VIP',
      'completed_orders_count': 3,
      'completed_orders_total': '25.50',
      'orders': [],
    };

void main() {
  late MockApiClient apiClient;
  late CustomersRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = CustomersRepository(apiClient);
  });

  test('getCustomers parses the paginated customer response', () async {
    final responseData = {
      'success': true,
      'data': [customerJson()],
      'meta': {
        'current_page': 1,
        'last_page': 2,
        'per_page': 20,
        'total': 21,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/customers'),
      ),
    );

    final page = await repository.getCustomers(
      search: 'John',
      branchId: 1,
      page: 1,
      perPage: 20,
    );

    expect(page.data, hasLength(1));
    expect(page.data.single.id, 5);
    expect(page.data.single.name, 'John Doe');
    expect(page.currentPage, 1);
    expect(page.lastPage, 2);
    expect(page.total, 21);
  });

  test('getCustomer parses a customer response', () async {
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: {
          'success': true,
          'data': customerJson(),
        },
        requestOptions: RequestOptions(path: '/customers/5'),
      ),
    );

    final customer = await repository.getCustomer(5);

    expect(customer.id, 5);
    expect(customer.name, 'John Doe');
    expect(customer.completedOrdersCount, 3);
    expect(customer.completedOrdersTotal, 25.50);
  });

  test('createCustomer parses the created customer response', () async {
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: {
          'success': true,
          'data': customerJson(id: 6, name: 'Jane Doe'),
        },
        requestOptions: RequestOptions(path: '/customers'),
      ),
    );

    final customer = await repository.createCustomer(
      name: 'Jane Doe',
      phone: '098765432',
      email: 'jane@example.com',
      notes: 'New customer',
      branchId: 1,
    );

    expect(customer.id, 6);
    expect(customer.name, 'Jane Doe');
  });

  test('updateCustomer parses the updated customer response', () async {
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: {
          'success': true,
          'data': customerJson(name: 'John Updated'),
        },
        requestOptions: RequestOptions(path: '/customers/5'),
      ),
    );

    final customer = await repository.updateCustomer(
      id: 5,
      name: 'John Updated',
      phone: '012345678',
      email: 'john@example.com',
      notes: 'Updated',
    );

    expect(customer.id, 5);
    expect(customer.name, 'John Updated');
  });

  test('deleteCustomer sends a delete request', () async {
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: {
          'success': true,
          'message': 'Customer deactivated successfully.',
        },
        requestOptions: RequestOptions(path: '/customers/5'),
      ),
    );

    await repository.deleteCustomer(5);

    verify(
      () => apiClient.request<Response<dynamic>>(any()),
    ).called(1);
  });

  test('getCustomerOrders parses the paginated order response', () async {
    final responseData = {
      'success': true,
      'data': [
        {
          'id': 12,
          'uuid': 'order-uuid-12',
          'branch_id': 1,
          'user_id': 2,
          'customer_id': 5,
          'table_id': null,
          'order_type': 'takeaway',
          'status': 'completed',
          'subtotal': '25.00',
          'discount_total': '0.00',
          'tax_total': '0.50',
          'total': '25.50',
          'held_at': null,
          'completed_at': '2026-09-30T10:00:00Z',
          'created_at': '2026-09-30T09:50:00Z',
          'items': [],
        },
      ],
      'meta': {
        'current_page': 1,
        'last_page': 2,
        'per_page': 20,
        'total': 21,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/customers/5/orders'),
      ),
    );

    final page = await repository.getCustomerOrders(
      customerId: 5,
      page: 1,
      perPage: 20,
    );

    expect(page.data, hasLength(1));
    expect(page.data.single.id, 12);
    expect(page.data.single.customerId, 5);
    expect(page.data.single.total, 25.50);
    expect(page.currentPage, 1);
    expect(page.lastPage, 2);
    expect(page.total, 21);
  });
}
