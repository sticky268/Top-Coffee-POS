import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/offline/pending_orders_screen.dart';

import '../../support/memory_local_store.dart';

class _Api extends Mock implements ApiClient {}

PendingOrder saved(String uuid, String status) => PendingOrder(
  uuid: uuid,
  userId: 1,
  branchId: 2,
  endpoint: '/orders',
  payload: const {'expected_total': 3.5},
  createdAt: DateTime.utc(2026, 10, 15, 12),
  fingerprint: uuid,
  status: status,
);

void main() {
  testWidgets('saved orders separate waiting and review on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingOrdersProvider.overrideWith(
            (ref) => Stream.value([
              saved('original-pending', 'pending'),
              saved('original-review', 'review'),
            ]),
          ),
        ],
        child: const MaterialApp(home: PendingOrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved on this device · action needed'), findsOneWidget);
    expect(
      find.text('1 waiting for server confirmation · 1 needing review'),
      findsOneWidget,
    );
    expect(find.text('Payment completed'), findsNothing);
    expect(find.text('Print Receipt'), findsNothing);
    expect(find.text('Reference: original-pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync waits for confirmation and suppresses repeated taps', (
    tester,
  ) async {
    final outbox = OrderOutbox(MemoryLocalStore(), newUuid: () => 'original');
    addTearDown(outbox.close);
    await outbox.prepare(
      userId: 1,
      branchId: 2,
      endpoint: '/orders',
      payload: const {'expected_total': 3.5},
    );
    final api = _Api();
    final response = Completer<Response<dynamic>>();
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) => response.future);
    final sync = OrderSync(outbox, api, () => (userId: 1, branchId: 2));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderScopeProvider.overrideWith(
            (ref) => (userId: 1, branchId: 2),
          ),
          orderOutboxProvider.overrideWithValue(outbox),
          orderSyncProvider.overrideWithValue(sync),
        ],
        child: const MaterialApp(home: PendingOrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pump();
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.text('Confirmed by server'), findsNothing);
    await tester.tap(find.text('Syncing…'));
    await tester.pump();
    verify(() => api.request<Response<dynamic>>(any())).called(1);
    response.complete(
      Response(
        requestOptions: RequestOptions(path: '/orders'),
        data: {
          'data': {
            'id': 42,
            'total': 3.5,
            'payment': {'method': 'cash'},
          },
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('All saved orders are confirmed by the server.'),
      findsWidgets,
    );
    expect((await outbox.list(1, 2)).single.uuid, 'original');
    expect((await outbox.list(1, 2)).single.orderId, 42);
    expect((await outbox.list(1, 2)).single.confirmedAt, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
