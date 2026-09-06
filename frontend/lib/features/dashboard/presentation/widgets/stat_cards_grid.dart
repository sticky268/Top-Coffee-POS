import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/dashboard_models.dart';

class StatCardsGrid extends StatelessWidget {
  const StatCardsGrid({super.key, required this.stats, required this.crossAxisCount});

  final DashboardStats stats;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$');

    final cards = [
      _StatCardData(
        label: "Today's Sales",
        value: currency.format(stats.todaysSales),
        icon: Icons.point_of_sale,
        color: Colors.green,
      ),
      _StatCardData(
        label: "Today's Orders",
        value: '${stats.todaysOrders}',
        icon: Icons.receipt_long,
        color: Colors.blue,
      ),
      _StatCardData(
        label: 'Average Order',
        value: currency.format(stats.averageOrderValue),
        icon: Icons.trending_up,
        color: Colors.purple,
      ),
      _StatCardData(
        label: 'Low Stock',
        value: '${stats.lowStockItemCount} items',
        icon: Icons.warning_amber_rounded,
        color: stats.lowStockItemCount > 0 ? Colors.orange : Colors.grey,
      ),
    ];

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      // 1.45 rather than 1.6 — gives cells a little more height headroom
      // before the responsive tier below even has to kick in. This alone
      // doesn't guarantee no overflow (see _StatCard for the actual fix);
      // it just means the compact tier is needed less often.
      childAspectRatio: 1.45,
      children: [for (final c in cards) _StatCard(data: c)],
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Genuine responsive tiering, not just a safety net: below this
          // height, use smaller padding/icon/fonts so the card looks right
          // at small sizes instead of merely "not crashing".
          final isCompact = constraints.maxHeight < 92;
          final padding = isCompact ? 10.0 : 16.0;
          final iconPadding = isCompact ? 5.0 : 8.0;
          final iconSize = isCompact ? 16.0 : 20.0;
          final valueFontSize = isCompact ? 17.0 : 22.0;
          final labelFontSize = isCompact ? 11.0 : 14.0;
          final gap = isCompact ? 4.0 : 8.0;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // mainAxisSize.max (the Column default) + Expanded below is
              // what actually prevents overflow: the icon badge and the
              // label get their fixed natural size, and Expanded gives the
              // value text *exactly* whatever height is left over — even
              // if that's very little — rather than assuming there's
              // always enough room for a full-size headline.
              children: [
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(data.icon, color: data.color, size: iconSize),
                ),
                SizedBox(height: gap),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        data.value,
                        maxLines: 1,
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: valueFontSize),
                      ),
                    ),
                  ),
                ),
                Text(
                  data.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: labelFontSize,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
