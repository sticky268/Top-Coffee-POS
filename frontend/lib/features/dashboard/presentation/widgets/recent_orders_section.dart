import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/dashboard_models.dart';
import 'order_status_presentation.dart';

class RecentOrdersSection extends StatelessWidget {
  const RecentOrdersSection({super.key, required this.orders});

  final List<RecentOrder> orders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No recent orders',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _RecentOrderTile(order: orders[index]),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final RecentOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = DateFormat('h:mm a').format(order.time);
    final currency = NumberFormat.currency(symbol: '\$');
    final statusColor = order.status.color(theme.colorScheme);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(order.status.icon, color: statusColor, size: 20),
      ),
      title: Text(
        '${order.orderNumber} • ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
      ),
      subtitle: Text(
        [
          timeLabel,
          if (order.customerOrTable != null) order.customerOrTable!,
        ].join(' · '),
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
            order.status.label,
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
