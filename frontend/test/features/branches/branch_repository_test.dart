import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/branches/data/branch_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late BranchRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = BranchRepository(apiClient);
  });

  test('getBranches parses the branch list response', () async {
    final responseData = {
      'success': true,
      'data': [
        {
          'id': 1,
          'name': 'Riverside',
          'code': 'PP-01',
          'address': 'Phnom Penh',
          'phone': '012345678',
          'timezone': 'Asia/Phnom_Penh',
          'is_active': true,
          'users_count': 5,
          'created_at': '2026-09-28T10:00:00.000000Z',
          'updated_at': '2026-09-28T10:00:00.000000Z',
        },
        {
          'id': 2,
          'name': 'BKK1',
          'code': 'PP-02',
          'address': null,
          'phone': null,
          'timezone': 'Asia/Phnom_Penh',
          'is_active': false,
          'users_count': 2,
          'created_at': null,
          'updated_at': null,
        },
      ],
      'meta': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 20,
        'total': 2,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/branches'),
      ),
    );

    final page = await repository.getBranches();

    expect(page.data, hasLength(2));
    expect(page.data.first.id, 1);
    expect(page.data.first.name, 'Riverside');
    expect(page.data.first.code, 'PP-01');
    expect(page.data.first.address, 'Phnom Penh');
    expect(page.data.first.usersCount, 5);
    expect(page.data.first.isActive, isTrue);
    expect(page.data[1].name, 'BKK1');
    expect(page.data[1].isActive, isFalse);
    expect(page.currentPage, 1);
    expect(page.lastPage, 1);
    expect(page.total, 2);
    expect(page.hasNextPage, isFalse);
  });

  test('getBranch parses the branch response', () async {
    final responseData = {
      'success': true,
      'data': {
        'id': 1,
        'name': 'Riverside',
        'code': 'PP-01',
        'address': 'Phnom Penh',
        'phone': '012345678',
        'timezone': 'Asia/Phnom_Penh',
        'is_active': true,
        'users_count': 5,
        'created_at': null,
        'updated_at': null,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/branches/1'),
      ),
    );

    final branch = await repository.getBranch(1);

    expect(branch.id, 1);
    expect(branch.name, 'Riverside');
    expect(branch.code, 'PP-01');
    expect(branch.usersCount, 5);
    expect(branch.isActive, isTrue);
  });

  test('createBranch parses the created branch response', () async {
    final responseData = {
      'success': true,
      'data': {
        'id': 3,
        'name': 'Toul Kork',
        'code': 'PP-03',
        'address': 'Toul Kork, Phnom Penh',
        'phone': '011111111',
        'timezone': 'Asia/Phnom_Penh',
        'is_active': true,
        'users_count': 0,
        'created_at': null,
        'updated_at': null,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/branches'),
      ),
    );

    final branch = await repository.createBranch(
      name: 'Toul Kork',
      code: 'PP-03',
      address: 'Toul Kork, Phnom Penh',
      phone: '011111111',
      timezone: 'Asia/Phnom_Penh',
    );

    expect(branch.id, 3);
    expect(branch.name, 'Toul Kork');
    expect(branch.code, 'PP-03');
    expect(branch.usersCount, 0);
    expect(branch.isActive, isTrue);
  });

  test('updateBranch parses the updated branch response', () async {
    final responseData = {
      'success': true,
      'data': {
        'id': 1,
        'name': 'Riverside Updated',
        'code': 'PP-01',
        'address': 'Updated Address',
        'phone': '099999999',
        'timezone': 'Asia/Phnom_Penh',
        'is_active': false,
        'users_count': 5,
        'created_at': null,
        'updated_at': null,
      },
    };

    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: responseData,
        requestOptions: RequestOptions(path: '/branches/1'),
      ),
    );

    final branch = await repository.updateBranch(
      id: 1,
      name: 'Riverside Updated',
      address: 'Updated Address',
      phone: '099999999',
      isActive: false,
    );

    expect(branch.id, 1);
    expect(branch.name, 'Riverside Updated');
    expect(branch.address, 'Updated Address');
    expect(branch.phone, '099999999');
    expect(branch.isActive, isFalse);
  });

  test('deleteBranch sends a delete request', () async {
    when(() => apiClient.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        data: {
          'success': true,
          'message': 'Branch deleted successfully',
        },
        requestOptions: RequestOptions(path: '/branches/1'),
      ),
    );

    await repository.deleteBranch(1);

    verify(() => apiClient.request<Response<dynamic>>(any())).called(1);
  });
}