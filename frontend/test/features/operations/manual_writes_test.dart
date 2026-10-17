import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/expenses/data/expenses_repository.dart';
import 'package:top_coffee_pos/features/inventory/data/inventory_repository.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';

import '../../support/memory_local_store.dart';

class _Api extends Mock implements ApiClient {}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool timeout = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    final Object response;
    if (options.path.endsWith('/movements')) {
      response = {
        'data': {
          'movement': {'id': 9},
          'ingredient': {
            'id': 4,
            'name': 'Coffee',
            'unit': {'id': 1, 'name': 'Gram', 'abbreviation': 'g'},
            'current_stock': '12.000',
            'reorder_threshold': '1.000',
            'is_low_stock': false,
            'is_active': true,
          },
        },
      };
    } else if (options.path == '/expenses' && options.method == 'GET') {
      response = {
        'data': [],
        'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 0},
      };
    } else if (options.path == '/expenses/summary') {
      response = {
        'data': {
          'today': 0,
          'week': 0,
          'previous_week': 0,
          'month': 0,
          'previous_month': 0,
        },
      };
    } else {
      response = {
        'data': {
          'id': 8,
          'branch_id': 2,
          'expense_category_id': 3,
          'user_id': 1,
          'amount': '12.50',
          'description': null,
          'spent_at': '2026-10-17',
          'attachment_path': null,
        },
      };
    }
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Api api;
  late _Adapter adapter;
  late MemoryLocalStore store;
  late OperationsScope? scope;
  late OperationsRepository operations;

  setUp(() {
    api = _Api();
    adapter = _Adapter();
    store = MemoryLocalStore();
    scope = (userId: 1, branchId: 2);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.httpClientAdapter = adapter;
    when(() => api.dio).thenReturn(dio);
    when(() => api.request<Response<dynamic>>(any())).thenAnswer((call) => (call
        .positionalArguments
        .single as Future<Response<dynamic>> Function(Dio))(dio));
    operations = OperationsRepository(api, store, () => scope);
  });

  test(
      'expense list, summary, detail, update and delete use the selected branch',
      () async {
    final repo = ExpensesRepository(api, operations, branchId: 2);
    await repo.getExpenses();
    await repo.getExpenseSummary();
    await repo.getExpense(8);
    await repo.updateExpense(id: 8, amount: 12.50);
    await repo.deleteExpense(8);

    expect(adapter.requests, hasLength(5));
    for (final request in adapter.requests) {
      final values = request.method == 'PATCH'
          ? request.data as Map
          : request.queryParameters;
      expect(values['branch_id'], 2);
    }
  });

  test('stock timeout survives restart and retries the same saved request',
      () async {
    Future<void> record(OperationsRepository journal) async {
      await ApiInventoryRepository(api, journal).recordStockMovement(
          ingredientId: 4,
          type: 'adjustment',
          quantity: 2,
          reason: 'Correction');
    }

    adapter.timeout = true;
    await expectLater(record(operations), throwsA(isA<NetworkException>()));
    final original = (await operations.pending()).single['uuid'];
    adapter.timeout = false;
    final restarted = OperationsRepository(api, store, () => scope);
    await record(restarted);

    expect(adapter.requests.map((r) => (r.data as Map)['uuid']),
        everyElement(original));
    expect(await restarted.pending(), isEmpty);
  });

  test('expense timeout retries one request and preserves its selected branch',
      () async {
    Future<void> create(OperationsRepository journal) async {
      await ExpensesRepository(api, journal, branchId: 2)
          .createExpense(categoryId: 3, amount: 12.50, spentAt: '2026-10-17');
    }

    adapter.timeout = true;
    await expectLater(create(operations), throwsA(isA<NetworkException>()));
    final original = (await operations.pending()).single['uuid'];
    adapter.timeout = false;
    final restarted = OperationsRepository(api, store, () => scope);
    await create(restarted);

    expect(adapter.requests.map((r) => (r.data as Map)['uuid']),
        everyElement(original));
    expect(adapter.requests.map((r) => (r.data as Map)['branch_id']),
        everyElement(2));
    expect(await restarted.pending(), isEmpty);
  });

  test('a stale expense form cannot save into a different branch', () async {
    final repo = ExpensesRepository(api, operations, branchId: 2);
    scope = (userId: 1, branchId: 3);

    await expectLater(
        repo.createExpense(categoryId: 3, amount: 12.50, spentAt: '2026-10-17'),
        throwsA(isA<AuthException>()));

    expect(adapter.requests, isEmpty);
    expect(await operations.pending(), isEmpty);
  });
}
