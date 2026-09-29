import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/branch_models.dart';

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepository(ref.watch(apiClientProvider));
});

class BranchRepository {
  BranchRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<BranchListPage> getBranches({
    String? search,
    bool? isActive,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/branches',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (isActive != null) 'is_active': isActive,
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return BranchListPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<Branch> getBranch(int id) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/branches/$id'),
    );

    return Branch.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Branch> createBranch({
    required String name,
    required String code,
    String? address,
    String? phone,
    required String timezone,
    bool isActive = true,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/branches',
        data: {
          'name': name,
          'code': code,
          if (address != null && address.isNotEmpty) 'address': address,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'timezone': timezone,
          'is_active': isActive,
        },
      ),
    );

    return Branch.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Branch> updateBranch({
    required int id,
    String? name,
    String? code,
    String? address,
    String? phone,
    String? timezone,
    bool? isActive,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/branches/$id',
        data: {
          if (name != null) 'name': name,
          if (code != null) 'code': code,
          if (address != null) 'address': address,
          if (phone != null) 'phone': phone,
          if (timezone != null) 'timezone': timezone,
          if (isActive != null) 'is_active': isActive,
        },
      ),
    );

    return Branch.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteBranch(int id) async {
    await _apiClient.request(
      (dio) => dio.delete('/branches/$id'),
    );
  }
}