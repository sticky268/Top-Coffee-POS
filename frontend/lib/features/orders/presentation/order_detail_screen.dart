import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/order_detail_controller.dart';
import '../application/order_detail_state.dart';
import '../domain/order_models.dart';
import 'widgets/order_status_helpers.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailControllerProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: Text('Order #$orderId')),
      body: switch (state) {
        OrderDetailLoading() => const Center(child: CircularProgressIndicator()),
        OrderDetailError(:final message) => _DetailErrorView(
            message: message,
            onRetry: () => ref.read(orderDetailControllerProvider(orderId).notifier).refresh(),
          ),
        OrderDetailLoaded(:final order) => _OrderDetailBody(order: order),
      },
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final dateLabel =
        order.createdAt != null ? DateFormat('MMM d, yyyy · h:mm a').format(order.createdAt!) : 'Unknown date';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order.id}', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _InfoRow(label: 'Status', value: orderStatusLabel(order.status)),
                _InfoRow(label: 'Type', value: orderTypeLabel(order.orderType)),
                if (order.table != null)
                  _InfoRow(label: 'Table', value: order.table!.name),
                // Defensive per this feature's requirement — a historical
                // order's branch/cashier could be missing; never crash,
                // always show a sensible fallback.
                _InfoRow(label: 'Branch', value: order.branch?.name ?? 'Unknown'),
                _InfoRow(label: 'Cashier', value: order.cashier?.name ?? 'Unknown'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: order.items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No items recorded',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (final item in order.items)
                      ListTile(
                        title: Text(
                          item.variantName != null ? '${item.productName} — ${item.variantName}' : item.productName,
                        ),
                        subtitle: Text('${item.quantity} × ${currency.format(item.unitPrice)}'),
                        trailing: Text(currency.format(item.lineTotal), style: theme.textTheme.titleMedium),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryRow(label: 'Subtotal', value: currency.format(order.subtotal)),
                if (order.discountTotal > 0)
                  _SummaryRow(label: 'Discount', value: '- ${currency.format(order.discountTotal)}'),
                const Divider(height: 16),
                _SummaryRow(label: 'Total', value: currency.format(order.total), emphasize: true),
              ],
            ),
          ),
        ),
        if (order.payment != null || order.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final payment in (order.payments.isNotEmpty ? order.payments : [order.payment!])) ...[
                    _InfoRow(
                      label: 'Method',
                      value: paymentMethodLabel(payment.method),
                    ),
                    _InfoRow(
                      label: 'Status',
                      value: payment.status,
                    ),
                    _InfoRow(
                      label: 'Amount',
                      value: currency.format(payment.amount),
                    ),
                    if (payment.tendered != null)
                      _InfoRow(
                        label: 'Tendered',
                        value: currency.format(payment.tendered),
                      ),
                    if (payment.changeDue != null)
                      _InfoRow(
                        label: 'Change Due',
                        value: currency.format(payment.changeDue),
                      ),
                    if (order.payments.length > 1 && payment != order.payments.last)
                      const Divider(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        emphasize ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) : theme.textTheme.bodyLarge;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Could not load this order', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
