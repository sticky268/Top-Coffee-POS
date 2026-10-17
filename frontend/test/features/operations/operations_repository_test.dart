import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/local_store.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/features/purchasing/data/purchase_repository.dart';

class _Api extends Mock implements ApiClient {}

class _Memory extends LocalStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> entries(String prefix) async =>
      Map.fromEntries(values.entries.where((e) => e.key.startsWith(prefix)));
}

class _Adapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> headers = [];
  int status = 200;
  bool timeout = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(Map<String, dynamic>.from(options.data as Map));
    headers.add(Map<String, dynamic>.from(options.headers));
    if (timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? {
                'data': options.path == '/purchases'
                    ? {
                        'id': 5,
                        'branch_id': 2,
                        'supplier_id': 3,
                        'created_by': 1,
                        'total_cost': 6,
                        'purchased_at': '2026-10-14',
                        'supplier': {'id': 3, 'name': 'Supplier'},
                        'items': [],
                      }
                    : {'id': 5, 'status': 'closed'},
              }
            : {'message': 'Rejected'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Api api;
  late _Adapter adapter;
  late _Memory store;
  late OperationsScope? scope;
  late OperationsRepository repo;
  setUp(() {
    api = _Api();
    adapter = _Adapter();
    store = _Memory();
    scope = (userId: 1, branchId: 2);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.httpClientAdapter = adapter;
    when(() => api.dio).thenReturn(dio);
    repo = OperationsRepository(api, store, () => scope);
  });

  test('viewing a historical shift preserves the verified active shift',
      () async {
    when(() => api.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/shifts'),
        data: {
          'data': [
            {'id': 12, 'user_id': 1, 'status': 'open'},
          ],
        },
      ),
    );
    await repo.get('/shifts');
    expect(await store.read('active-shift:1:2'), '12');

    when(() => api.request<Response<dynamic>>(any())).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/shifts'),
        data: {
          'data': [
            {'id': 5, 'user_id': 1, 'status': 'closed'},
          ],
        },
      ),
    );
    await repo.get('/shifts', query: {'shift_id': 5});
    expect(await store.read('active-shift:1:2'), '12');

    // An unfiltered authoritative response can still invalidate a closed shift.
    await repo.get('/shifts');
    expect(await store.read('active-shift:1:2'), isNull);
  });

  test(
    'shift reads for another branch update only that branch cache',
    () async {
      await store.write('active-shift:1:2', '12');
      when(() => api.request<Response<dynamic>>(any())).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/shifts'),
          data: {
            'data': [
              {'id': 30, 'user_id': 1, 'status': 'open'},
            ],
          },
        ),
      );

      await repo.get('/shifts', branchId: 3);

      expect(await store.read('active-shift:1:2'), '12');
      expect(await store.read('active-shift:1:3'), '30');
    },
  );

  test(
    'refund PIN stays in the transient header and retry needs a fresh PIN',
    () async {
      adapter.timeout = true;
      await expectLater(
        repo.write(
            '/orders/7/refund',
            {
              'amount': 2,
              'reason': 'Correction',
            },
            managerPin: '836492'),
        throwsA(isA<NetworkException>()),
      );
      expect(adapter.headers.single['X-Manager-Pin'], '836492');
      expect(jsonEncode(store.values), isNot(contains('836492')));
      final saved = (await repo.pending()).single;
      final uuid = saved['uuid'];
      final restarted = OperationsRepository(api, store, () => scope);
      adapter.status = 422;
      adapter.timeout = false;
      await expectLater(
        restarted.retry(saved),
        throwsA(isA<UncertainOperationException>()),
      );
      expect(adapter.headers.last.containsKey('X-Manager-Pin'), isFalse);
      adapter.status = 200;
      await restarted.retry(
        (await restarted.pending()).single,
        managerPin: '749281',
      );
      expect(adapter.headers.last['X-Manager-Pin'], '749281');
      expect(adapter.requests.map((p) => p['uuid']), everyElement(uuid));
      expect(await restarted.pending(), isEmpty);
    },
  );

  test('credentials cannot enter the saved operation payload', () {
    expect(
      () => repo.write('/orders/7/refund', {'amount': 2, 'pin': '836492'}),
      throwsArgumentError,
    );
    expect(store.values, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test(
    'restart retries an uncertain financial operation with the original UUID',
    () async {
      adapter.timeout = true;
      await expectLater(
        repo.write('/orders/5/refund', {'amount': 3}),
        throwsA(isA<NetworkException>()),
      );
      final saved = (await repo.pending()).single;
      adapter.timeout = false;
      final restarted = OperationsRepository(api, store, () => scope);
      await restarted.write('/orders/5/refund', {'amount': 3});
      expect(adapter.requests.map((r) => r['uuid']).toSet(), {saved['uuid']});
      expect(await restarted.pending(), isEmpty);
    },
  );

  test(
    'loss of permission after an uncertain response cannot discard the request',
    () async {
      adapter.timeout = true;
      await expectLater(
        repo.write('/shifts/5/close', {'counted_cash': 20}),
        throwsA(isA<NetworkException>()),
      );
      adapter.timeout = false;
      adapter.status = 403;
      await expectLater(
        repo.retry((await repo.pending()).single),
        throwsA(isA<UncertainOperationException>()),
      );
      final saved = (await repo.pending()).single;
      expect(saved['rejected'], isFalse);
      await expectLater(
        repo.dismissRejected(saved),
        throwsA(isA<AuthException>()),
      );
      expect(await repo.pending(), hasLength(1));
    },
  );

  test(
    'a confirmed first-attempt validation rejection can be dismissed',
    () async {
      adapter.status = 422;
      await expectLater(
        repo.write('/stock/count', {'counted_stock': 3}),
        throwsA(isA<ApiException>()),
      );
      final saved = (await repo.pending()).single;
      expect(saved['rejected'], isTrue);
      await repo.dismissRejected(saved);
      expect(await repo.pending(), isEmpty);
    },
  );

  test(
    'purchase timeout survives restart and a new confirmed purchase gets a new UUID',
    () async {
      Future<void> create(ApiPurchaseRepository purchases) async {
        await purchases.createPurchase(
          branchId: 2,
          supplierId: 3,
          purchasedAt: DateTime(2026, 10, 14),
          items: [
            const PurchaseCreateItem(ingredientId: 4, quantity: 2, unitCost: 3),
          ],
        );
      }

      adapter.timeout = true;
      await expectLater(
        create(ApiPurchaseRepository(api, repo)),
        throwsA(isA<NetworkException>()),
      );
      final original = (await repo.pending()).single['uuid'];
      adapter.timeout = false;
      final restarted = OperationsRepository(api, store, () => scope);
      final purchases = ApiPurchaseRepository(api, restarted);
      await create(purchases);
      expect(adapter.requests[1]['uuid'], original);
      expect(await restarted.pending(), isEmpty);
      await create(purchases);
      expect(adapter.requests[2]['uuid'], isNot(original));
      expect(adapter.requests[2]['expected_user_id'], 1);
    },
  );

  test('pending requests are isolated by user and branch', () async {
    adapter.timeout = true;
    await expectLater(
      repo.write('/shifts', {'opening_cash': 20}),
      throwsA(isA<NetworkException>()),
    );
    final saved = (await repo.pending()).single;
    scope = (userId: 1, branchId: 3);
    expect(await repo.pending(), isEmpty);
    expect(() => repo.retry(saved), throwsA(isA<AuthException>()));
    scope = (userId: 2, branchId: 2);
    expect(await repo.pending(), isEmpty);
    scope = (userId: 1, branchId: 2);
    expect(await repo.pending(), hasLength(1));
  });
}
