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

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${order.orderNumber} • ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          [
            timeLabel,
            if (order.customerOrTable != null) order.customerOrTable!,
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final summary = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          currency.format(order.total),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            order.status.label,
            style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 500 ||
              MediaQuery.textScalerOf(context).scale(14) > 19;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(order.status.icon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          details,
                          const SizedBox(height: 12),
                          summary,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 16),
                          summary,
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
