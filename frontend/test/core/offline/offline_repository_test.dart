import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

import '../../support/memory_local_store.dart';

class MockApi extends Mock implements ApiClient {}

void main() {
  test(
      'temporary server failure uses the same scoped catalog fallback as an outage',
      () async {
    final api = MockApi();
    final repository =
        ApiPosRepository(api, localStore: MemoryLocalStore(), userId: () => 1);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/categories'),
              data: {
                'data': [
                  {'id': 1, 'name': 'Coffee', 'sort_order': 0}
                ]
              },
            ));
    await repository.getCategories(branchId: 2);
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const ServerException());

    expect((await repository.getCategories(branchId: 2)).single.name, 'Coffee');
    await expectLater(
        repository.getCategories(branchId: 3), throwsA(isA<ServerException>()));
  });

  test(
      'catalog fallback is isolated by cashier and branch; auth errors never use cache',
      () async {
    final store = MemoryLocalStore();
    final api = MockApi();
    var userId = 1;
    var cached = false;
    final repository = ApiPosRepository(api,
        localStore: store,
        userId: () => userId,
        onCachedCatalog: () => cached = true);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/categories'),
              data: {
                'data': [
                  {'id': 1, 'name': 'Coffee', 'sort_order': 0}
                ]
              },
            ));
    await repository.getCategories(branchId: 2);
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const NetworkException());
    expect((await repository.getCategories(branchId: 2)).single.name, 'Coffee');
    expect(cached, isTrue);
    await expectLater(repository.getCategories(branchId: 3),
        throwsA(isA<NetworkException>()));
    userId = 2;
    await expectLater(repository.getCategories(branchId: 2),
        throwsA(isA<NetworkException>()));
    userId = 1;
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const AuthException());
    await expectLater(
        repository.getCategories(branchId: 2), throwsA(isA<AuthException>()));
  });

  test(
      'failed checkout is durably queued; restart reuses the ID and confirms once',
      () async {
    final store = MemoryLocalStore();
    final api = MockApi();
    final outbox = OrderOutbox(store, newUuid: () => 'original');
    addTearDown(outbox.close);
    ApiPosRepository repo(OrderOutbox journal) =>
        ApiPosRepository(api, outbox: journal, userId: () => 1);
    const items = [
      CartItem(
          product: PosProduct(
              id: 3,
              name: 'Coffee',
              sku: null,
              description: null,
              category: null,
              price: 3.50,
              variants: []),
          quantity: 1)
    ];
    Future<OrderConfirmation> submit(ApiPosRepository repository) =>
        repository.createOrder(
            items: items,
            paymentMethod: 'cash',
            orderType: 'takeaway',
            tendered: 5,
            branchId: 2);
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const NetworkException());
    await expectLater(
        submit(repo(outbox)),
        throwsA(isA<QueuedOrderException>()
            .having((error) => error.uuid, 'uuid', 'original')));
    final pending = (await outbox.list(1, 2)).single;
    expect(pending.payload['expected_total'], 3.5);
    expect(pending.payload['expected_cashier_id'], 1);
    final restarted = OrderOutbox(store, newUuid: () => 'duplicate');
    addTearDown(restarted.close);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/orders'),
              data: {
                'data': {
                  'id': 42,
                  'total': 3.5,
                  'payment': {'method': 'cash'}
                }
              },
            ));
    expect((await submit(repo(restarted))).orderId, 42);
    final confirmed = (await restarted.list(1, 2)).single;
    expect(confirmed.uuid, pending.uuid);
    expect(confirmed.status, 'synced');
  });

  test('explicit UUID replays one sale but permits a separate identical sale',
      () async {
    final store = MemoryLocalStore();
    final outbox = OrderOutbox(store);
    addTearDown(outbox.close);
    final payload = <String, dynamic>{
      'branch_id': 2,
      'items': [
        {'product_id': 3, 'quantity': 1}
      ],
      'payment': {'method': 'cash', 'tendered': 5},
      'expected_total': 3.5,
    };

    final original = await outbox.prepare(
      userId: 1,
      branchId: 2,
      endpoint: '/orders',
      payload: {...payload, 'uuid': 'sale-a'},
    );
    final replay = await outbox.prepare(
      userId: 1,
      branchId: 2,
      endpoint: '/orders',
      payload: {...payload, 'uuid': 'sale-a'},
    );
    final separateSale = await outbox.prepare(
      userId: 1,
      branchId: 2,
      endpoint: '/orders',
      payload: {...payload, 'uuid': 'sale-b'},
    );

    expect(replay.uuid, original.uuid);
    expect(separateSale.uuid, isNot(original.uuid));
    expect(await outbox.list(1, 2), hasLength(2));
  });

  test(
      'matching ignores payment details, preserves scope and releases confirmed sales',
      () async {
    final outbox = OrderOutbox(MemoryLocalStore());
    addTearDown(outbox.close);
    final payload = <String, dynamic>{
      'order_type': 'takeaway',
      'items': [
        {'product_id': 3, 'quantity': 1},
        {'product_id': 4, 'quantity': 2},
      ],
      'payment': {'method': 'cash', 'tendered': 5},
    };
    final original = await outbox.prepare(
        userId: 1,
        branchId: 2,
        endpoint: '/orders',
        payload: {...payload, 'uuid': 'original'},
        checkUnresolvedSales: true);
    final changed = {
      ...payload,
      'uuid': 'new',
      'shift_id': 99,
      'items': (payload['items'] as List).reversed.toList(),
      'payment': {'method': 'card'}
    };
    await expectLater(
        outbox.prepare(
            userId: 1,
            branchId: 2,
            endpoint: '/orders',
            payload: changed,
            checkUnresolvedSales: true),
        throwsA(isA<UnresolvedOrderException>()));
    await outbox.prepare(
        userId: 2,
        branchId: 2,
        endpoint: '/orders',
        payload: changed,
        checkUnresolvedSales: true);
    await outbox.prepare(
        userId: 1,
        branchId: 3,
        endpoint: '/orders',
        payload: changed,
        checkUnresolvedSales: true);
    expect(await outbox.list(1, 2), hasLength(1));
    await outbox.finish(original, orderId: 42);
    await outbox.prepare(
        userId: 1,
        branchId: 2,
        endpoint: '/orders',
        payload: changed,
        checkUnresolvedSales: true);
    expect(await outbox.list(1, 2), hasLength(2));
  });

  test(
      'reopened checkout blocks a new UUID until separate sale is acknowledged',
      () async {
    final store = MemoryLocalStore();
    final api = MockApi();
    final original = OrderOutbox(store);
    final restarted = OrderOutbox(store);
    addTearDown(original.close);
    addTearDown(restarted.close);
    const items = [
      CartItem(
          product: PosProduct(
              id: 3,
              name: 'Coffee',
              sku: null,
              description: null,
              category: null,
              price: 3.5,
              variants: []),
          quantity: 1)
    ];
    Future<OrderConfirmation> submit(OrderOutbox outbox, String uuid,
            {List<String> acknowledged = const []}) =>
        ApiPosRepository(api, outbox: outbox, userId: () => 1).createOrder(
            items: items,
            requestUuid: uuid,
            paymentMethod: 'cash',
            orderType: 'takeaway',
            tendered: 5,
            branchId: 2,
            acknowledgedPendingUuids: acknowledged);
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const NetworkException());
    await expectLater(
        submit(original, 'sale-a'), throwsA(isA<QueuedOrderException>()));
    await expectLater(
        submit(restarted, 'sale-b'),
        throwsA(isA<UnresolvedOrderException>()
            .having((e) => e.uuid, 'original reference', 'sale-a')));
    expect(await restarted.list(1, 2), hasLength(1));
    verify(() => api.request<Response<dynamic>>(any())).called(1);
    await expectLater(
        submit(restarted, 'sale-a'), throwsA(isA<QueuedOrderException>()));
    expect(await restarted.list(1, 2), hasLength(1));
    await expectLater(submit(restarted, 'sale-b', acknowledged: ['sale-a']),
        throwsA(isA<QueuedOrderException>()));
    expect(await restarted.list(1, 2), hasLength(2));
  });
}
