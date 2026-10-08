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
        submit(repo(outbox)), throwsA(isA<QueuedOrderException>()));
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
}
