import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';

import '../../support/memory_local_store.dart';

class MockApi extends Mock implements ApiClient {}

Response<dynamic> accepted(int id) =>
    Response(requestOptions: RequestOptions(path: '/orders'), data: {
      'data': {
        'id': id,
        'total': 3.5,
        'payment': {'method': 'cash'}
      }
    });

void main() {
  late OrderOutbox outbox;
  late MockApi api;
  OrderScope? scope;
  late OrderSync sync;
  setUp(() {
    var sequence = 0;
    outbox = OrderOutbox(MemoryLocalStore(), newUuid: () => '${sequence++}');
    api = MockApi();
    scope = (userId: 1, branchId: 2);
    sync = OrderSync(outbox, api, () => scope);
  });
  tearDown(() => outbox.close());
  Future<PendingOrder> prepare(int quantity) =>
      outbox.prepare(userId: 1, branchId: 2, endpoint: '/orders', payload: {
        'items': [
          {'quantity': quantity}
        ],
        'branch_id': 2
      });

  test('reconnect acknowledges a saved order, concurrent syncs send only once',
      () async {
    await prepare(1);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => accepted(42));
    await Future.wait([sync.sync(), sync.sync()]);
    final records = await outbox.list(1, 2);
    expect(records.single.status, 'synced');
    expect(records.single.orderId, 42);
    await sync.sync();
    verify(() => api.request<Response<dynamic>>(any())).called(1);
  });

  test('network failure stops the batch and preserves both requests', () async {
    await prepare(1);
    await prepare(2);
    when(() => api.request<Response<dynamic>>(any()))
        .thenThrow(const NetworkException());
    await sync.sync();
    expect((await outbox.list(1, 2)).map((order) => order.status),
        ['pending', 'pending']);
    verify(() => api.request<Response<dynamic>>(any())).called(1);
  });

  test('business rejection remains for review and does not block another sale',
      () async {
    await prepare(1);
    await prepare(2);
    var sends = 0;
    when(() => api.request<Response<dynamic>>(any())).thenAnswer((_) async {
      if (sends++ == 0) throw const ValidationException({}, 'Not enough stock');
      return accepted(43);
    });
    await sync.sync();
    final records = await outbox.list(1, 2);
    expect(records.map((order) => order.status), ['review', 'synced']);
    await sync.sync();
    expect(sends, 2);
  });

  test('logout or branch change stops processing the previous scope', () async {
    await prepare(1);
    await prepare(2);
    final response = Completer<Response<dynamic>>();
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) => response.future);
    final running = sync.sync();
    await Future<void>.delayed(Duration.zero);
    scope = (userId: 2, branchId: 3);
    response.complete(accepted(42));
    await running;
    expect((await outbox.list(1, 2)).map((order) => order.status),
        ['synced', 'pending']);
    await sync.sync();
    verify(() => api.request<Response<dynamic>>(any())).called(1);
    scope = null;
    await sync.sync();
    verifyNoMoreInteractions(api);
  });
}
