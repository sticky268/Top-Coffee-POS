import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/staff_models.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(apiClientProvider));
});

class StaffRepository {
  StaffRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<StaffListPage> getStaff({
    String? search,
    String? role,
    int? branchId,
    bool? isActive,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/users',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (role != null && role.isNotEmpty) 'role': role,
          if (branchId != null) 'branch_id': branchId,
          if (isActive != null) 'is_active': isActive,
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return StaffListPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<StaffMember> getStaffMember(int id) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/users/$id'),
    );

    return StaffMember.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<StaffMember> createStaff({
    required String name,
    required String email,
    String? phone,
    required String password,
    required String role,
    required List<int> branchIds,
    required int primaryBranchId,
    bool isActive = true,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/users',
        data: {
          'name': name,
          'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'password': password,
          'role': role,
          'branch_ids': branchIds,
          'primary_branch_id': primaryBranchId,
          'is_active': isActive,
        },
      ),
    );

    return StaffMember.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<StaffMember> updateStaff({
    required int id,
    String? name,
    String? email,
    String? phone,
    String? password,
    String? role,
    List<int>? branchIds,
    int? primaryBranchId,
    bool? isActive,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/users/$id',
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
          if (password != null && password.isNotEmpty)
            'password': password,
          if (role != null) 'role': role,
          if (branchIds != null) 'branch_ids': branchIds,
          if (primaryBranchId != null)
            'primary_branch_id': primaryBranchId,
          if (isActive != null) 'is_active': isActive,
        },
      ),
    );

    return StaffMember.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteStaff(int id) async {
    await _apiClient.request(
      (dio) => dio.delete('/users/$id'),
    );
  }
}
