import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/order_models.dart';
import 'order_status_helpers.dart';

class OrderListTile extends StatelessWidget {
  const OrderListTile({super.key, required this.order, required this.onTap});

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final statusColor = orderStatusColor(order.status, theme.colorScheme);
    final dateLabel = order.createdAt != null
        ? DateFormat('MMM d, h:mm a').format(order.createdAt!)
        : '—';

    final subtitleParts = <String>[
      dateLabel,
      orderTypeLabel(order.orderType),
      if (order.cashier != null) order.cashier!.name,
    ];

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Text(
          '#${order.id}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: statusColor,
          ),
        ),
      ),
      title: Text('Order #${order.id}'),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            currency.format(order.total),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            orderStatusLabel(order.status),
            style: theme.textTheme.labelLarge?.copyWith(
              color: statusColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
