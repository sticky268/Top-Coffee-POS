import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/customer_models.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(ref.watch(apiClientProvider));
});

class CustomersRepository {
  CustomersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<CustomerListPage> getCustomers({
    String? search,
    int? branchId,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/customers',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (branchId != null) 'branch_id': branchId,
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return CustomerListPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<Customer> getCustomer(int id) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/customers/$id'),
    );

    return Customer.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? notes,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/customers',
        data: {
          'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          if (notes != null) 'notes': notes,
          if (branchId != null) 'branch_id': branchId,
        },
      ),
    );

    return Customer.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Customer> updateCustomer({
    required int id,
    String? name,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/customers/$id',
        data: {
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          if (notes != null) 'notes': notes,
        },
      ),
    );

    return Customer.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteCustomer(int id) async {
    await _apiClient.request(
      (dio) => dio.delete('/customers/$id'),
    );
  }

  Future<CustomerOrderPage> getCustomerOrders({
    required int customerId,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/customers/$customerId/orders',
        queryParameters: {
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return CustomerOrderPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
