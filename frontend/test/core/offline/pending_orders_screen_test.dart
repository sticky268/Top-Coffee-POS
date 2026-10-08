import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/offline/pending_orders_screen.dart';

void main() {
  for (final status in ['pending', 'synced']) {
    testWidgets(
        '$status order fits a small screen and only confirmed sales expose receipts',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = PendingOrder(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        userId: 1,
        branchId: 2,
        endpoint: '/orders',
        payload: {'expected_total': 3.5},
        createdAt: DateTime.utc(2026, 10, 8),
        fingerprint: 'fixture',
        status: status,
        orderId: status == 'synced' ? 42 : null,
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          pendingOrdersProvider.overrideWith((ref) => Stream.value([order]))
        ],
        child: const MaterialApp(home: PendingOrdersScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Payment completed'), findsNothing);
      expect(find.text('Print Receipt'),
          status == 'synced' ? findsOneWidget : findsNothing);
      expect(find.text('E-Receipt'),
          status == 'synced' ? findsOneWidget : findsNothing);
      expect(
          find.text(status == 'synced'
              ? 'Confirmed by server'
              : 'Waiting for connection'),
          findsOneWidget);
    });
  }
}
