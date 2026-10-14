import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/receipt_action_buttons.dart';
import 'order_outbox.dart';
import 'order_sync.dart';

class PendingOrdersScreen extends ConsumerStatefulWidget {
  const PendingOrdersScreen({super.key});
  @override
  ConsumerState<PendingOrdersScreen> createState() =>
      _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends ConsumerState<PendingOrdersScreen> {
  bool _busy = false;
  Future<void> _sync({PendingOrder? order}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (order != null) await ref.read(orderOutboxProvider).retry(order);
      await ref.read(orderSyncProvider).sync();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not sync: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(pendingOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Orders'), actions: [
        TextButton(
            onPressed: _busy ? null : () => _sync(),
            child: Text(_busy ? 'Syncing...' : 'Sync now')),
      ]),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load saved orders: $error')),
        data: (orders) => orders.isEmpty
            ? const Center(
                child: Text('No orders saved on this device for this branch.'))
            : ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                    'Orders awaiting confirmation are not completed sales. Keep them until the server confirms them. Review errors before collecting or refunding payment.'),
                const SizedBox(height: 16),
                for (final order in orders)
                  Card(
                      child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reference: ${order.uuid}'),
                          Text(order.status == 'synced'
                              ? 'Confirmed by server'
                              : order.status == 'review'
                                  ? 'Needs review'
                                  : 'Waiting for connection'),
                          Text('Saved: ${order.createdAt.toLocal()}'),
                          if (order.payload['expected_total'] != null)
                            Text(
                                'Reviewed total: ${order.payload['expected_total']}'),
                          if (order.error != null) Text(order.error!),
                          if (order.status == 'review')
                            TextButton(
                              onPressed:
                                  _busy ? null : () => _sync(order: order),
                              child: const Text('Retry original request'),
                            ),
                          if (order.status == 'synced' &&
                              order.orderId != null) ...[
                            TextButton(
                                onPressed: () =>
                                    context.go('/orders/${order.orderId}'),
                                child: const Text('Open order')),
                            if (order.endpoint == '/orders')
                              ReceiptActionButtons(orderId: order.orderId!),
                          ],
                        ]),
                  )),
              ]),
      ),
    );
  }
}
