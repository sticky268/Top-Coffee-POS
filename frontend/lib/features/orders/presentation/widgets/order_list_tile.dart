import 'package:flutter/material.dart';
import '../../../../core/theme/coffee_studio_theme.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../domain/order_models.dart';
import 'order_status_helpers.dart';

class OrderListTile extends StatelessWidget {
  const OrderListTile({super.key, required this.order, required this.onTap});

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = orderStatusColor(order.status, scheme);
    final dateLabel = order.createdAt != null
        ? DateFormat('MMM d, h:mm a').format(order.createdAt!)
        : 'Time unavailable';
    final statusIcon = switch (order.status) {
      'completed' => Icons.check_circle_outline_rounded,
      'cancelled' => Icons.cancel_outlined,
      'held' => Icons.pause_circle_outline_rounded,
      _ => Icons.schedule_rounded,
    };
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon, size: 16, color: statusColor),
        const SizedBox(width: 6),
        Flexible(
            child: Text(orderStatusLabel(order.status),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor, fontWeight: FontWeight.w700))),
      ]),
    );
    final amount = Text(NumberFormat.currency(symbol: '\$').format(order.total),
        maxLines: 1,
        softWrap: false,
        style:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700));
    if (CoffeeStudioTheme.active(context) &&
        MediaQuery.sizeOf(context).width >= 900 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20) {
      return Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant)),
        child: pos_ui.ActionSurface(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order ${order.displayOrderReference}',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                                '$dateLabel · ${orderTypeLabel(order.orderType)}',
                                style: theme.textTheme.bodySmall),
                          ])),
                  Expanded(
                      flex: 2,
                      child:
                          Align(alignment: Alignment.centerLeft, child: badge)),
                  amount,
                  const SizedBox(width: 16),
                  const Icon(Icons.chevron_right, size: 20),
                ]))),
      );
    }
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant)),
      child: pos_ui.ActionSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.receipt_long_outlined,
                      size: 22, color: scheme.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Order ${order.displayOrderReference}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$dateLabel · ${orderTypeLabel(order.orderType)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ])),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ]),
            if (order.cashier != null) ...[
              const SizedBox(height: 12),
              Text(order.cashier!.name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      badge,
                      const SizedBox(height: 10),
                      SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: amount)),
                    ]);
              }
              return Row(children: [
                badge,
                const SizedBox(width: 12),
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: amount))
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}
