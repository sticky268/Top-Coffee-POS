import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/dashboard_models.dart';

/// A deliberately simple bar chart built from plain widgets (no charting
/// package) — each bar's height is a fraction of the row's max value,
/// via FractionallySizedBox inside a fixed-height row.
class SalesOverviewChart extends StatelessWidget {
  const SalesOverviewChart({super.key, required this.data, this.height = 160});

  final List<SalesDataPoint> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No sales data yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxValue = data.map((d) => d.total).reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final dayFormat = DateFormat('E'); // Mon, Tue, ...

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (point.total / safeMax).clamp(
                            0.03,
                            1.0,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayFormat.format(point.date),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
