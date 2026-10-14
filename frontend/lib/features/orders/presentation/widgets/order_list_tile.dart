import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/page_content.dart';
import '../../../pos/presentation/widgets/checkout_summary.dart';
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

    return RecordTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(Icons.receipt_long_outlined, color: statusColor),
      ),
      title: 'Order ${order.displayOrderReference}',
      subtitle: subtitleParts.join(' · '),
      trailing: const Icon(Icons.chevron_right),
      details: CheckoutAmountRow(
        label: orderStatusLabel(order.status),
        value: currency.format(order.total),
        valueColor: statusColor,
      ),
    );
  }
}
