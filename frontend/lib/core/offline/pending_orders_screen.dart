import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../network/api_exceptions.dart';
import '../widgets/receipt_action_buttons.dart';
import 'order_outbox.dart';
import 'order_sync.dart';
import 'order_sync_summary.dart';

class PendingOrdersScreen extends ConsumerStatefulWidget {
  const PendingOrdersScreen({super.key});
  @override
  ConsumerState<PendingOrdersScreen> createState() =>
      _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends ConsumerState<PendingOrdersScreen> {
  bool _busy = false;

  Future<void> _sync({PendingOrder? order}) async {
    final selected = ref.read(orderScopeProvider);
    if (_busy || selected == null) return;
    if (order != null &&
        (order.userId != selected.userId || order.branchId != selected.branchId)) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (order != null) await ref.read(orderOutboxProvider).retry(order);
      if (ref.read(orderScopeProvider) != selected) return;
      await ref.read(orderSyncProvider).sync();
      if (!mounted || ref.read(orderScopeProvider) != selected) return;
      final saved = await ref
          .read(orderOutboxProvider)
          .list(selected.userId, selected.branchId);
      if (!mounted || ref.read(orderScopeProvider) != selected) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OrderSyncSummary.fromOrders(saved).description)),
      );
    } catch (error) {
      if (mounted && ref.read(orderScopeProvider) == selected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not confirm saved orders. Keep them and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deviceTime(DateTime value) =>
      DateFormat.yMMMd().add_jm().format(value.toLocal());

  Widget _summary(List<PendingOrder> orders) {
    final summary = OrderSyncSummary.fromOrders(orders);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary.needsAttention
                  ? 'Saved on this device · action needed'
                  : 'Saved orders confirmed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(summary.description),
            Text('${summary.confirmed} confirmed by server'),
            if (summary.latestConfirmation != null)
              Text(
                'Last order confirmed (device time): '
                '${_deviceTime(summary.latestConfirmation!)}',
              ),
            if (summary.needsAttention) ...[
              const SizedBox(height: 8),
              const Text(
                'These orders remain on this device. Automatic sync runs while '
                'the signed-in app is open. Orders needing review require your '
                'attention; Sync now does not retry them automatically.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _order(PendingOrder order) {
    final total = num.tryParse('${order.payload['expected_total']}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              order.status == 'synced' && order.orderId != null
                  ? 'Order #${order.orderId}'
                  : 'Saved order',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              order.status == 'synced'
                  ? 'Confirmed by server'
                  : order.status == 'review'
                  ? 'Needs review'
                  : order.status == 'pending'
                  ? 'Waiting for connection'
                  : 'Needs review',
            ),
            if (order.status != 'synced')
              const Text('Saved on this device; completion is not confirmed.'),
            Text('Saved (device time): ${_deviceTime(order.createdAt)}'),
            if (total != null && total.isFinite)
              Text(
                'Reviewed total: '
                '${NumberFormat.currency(symbol: '\$').format(total)}',
              ),
            if (order.error != null) Text(order.error!),
            if (order.status == 'review')
              TextButton(
                onPressed: _busy ? null : () => _sync(order: order),
                child: const Text('Retry original request'),
              ),
            if (order.status == 'synced' && order.orderId != null) ...[
              TextButton(
                onPressed: () => context.go('/orders/${order.orderId}'),
                child: const Text('Open order'),
              ),
              if (order.endpoint == '/orders')
                ReceiptActionButtons(orderId: order.orderId!),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Request details'),
              children: [
                SelectableText('Reference: ${order.uuid}'),
                Text('Request: ${order.endpoint}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(pendingOrdersProvider);
    return Scaffold(
      appBar: PageAppBar(
        title: const Text('Pending Orders'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _sync(),
            child: Text(_busy ? 'Syncing…' : 'Sync now'),
          ),
        ],
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not read saved orders. Keep the app data on this '
                  'device and try again.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(pendingOrdersProvider),
                  child: const Text('Retry loading'),
                ),
              ],
            ),
          ),
        ),
        data: (saved) => saved.isEmpty
            ? const Center(
                child: Text(
                  'No orders saved on this device for this branch.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summary(saved),
                  const SizedBox(height: 16),
                  const Text(
                    'Orders awaiting confirmation are not completed sales. '
                    'Keep them until the server confirms them. Review errors '
                    'before collecting or refunding payment.',
                  ),
                  const SizedBox(height: 16),
                  for (final order in saved) _order(order),
                ],
              ),
      ),
    );
  }
}
