import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/reports_controller.dart';
import '../application/reports_state.dart';
import '../domain/reports_models.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: switch (state) {
        ReportsLoading() => const Center(child: CircularProgressIndicator()),
        ReportsError(:final message) => _ErrorView(
          message: message,
          onRetry: () {
            ref.read(reportsControllerProvider.notifier).refresh();
          },
        ),
        ReportsLoaded(:final report, :final dateFrom, :final dateTo) =>
          _ReportsContent(
            report: report,
            dateFrom: dateFrom,
            dateTo: dateTo,
            selectedRange: ref
                .read(reportsControllerProvider.notifier)
                .selectedRange,
            onRangeSelected: (range) {
              ref.read(reportsControllerProvider.notifier).selectRange(range);
            },
            onRefresh: () {
              return ref.read(reportsControllerProvider.notifier).refresh();
            },
          ),
      },
    );
  }
}

class _ReportsContent extends StatelessWidget {
  const _ReportsContent({
    required this.report,
    required this.dateFrom,
    required this.dateTo,
    required this.selectedRange,
    required this.onRangeSelected,
    required this.onRefresh,
  });

  final ReportsData report;
  final DateTime dateFrom;
  final DateTime dateTo;
  final ReportsDateRange selectedRange;
  final ValueChanged<ReportsDateRange> onRangeSelected;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd MMM yyyy');

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _DateRangeSelector(
            selectedRange: selectedRange,
            onSelected: onRangeSelected,
          ),
          const SizedBox(height: 8),
          Text(
            '${dateFormat.format(dateFrom)} - ${dateFormat.format(dateTo)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SummaryGrid(summary: report.summary),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Sales Overview',
            icon: Icons.bar_chart_outlined,
            child:
                dateFrom.year == dateTo.year &&
                    dateFrom.month == dateTo.month &&
                    dateFrom.day == dateTo.day
                ? _HourlySalesChart(data: report.hourlySales)
                : _SalesOverviewChart(data: report.salesOverview),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SectionCard(
                  title: 'Payment Methods',
                  icon: Icons.payments_outlined,
                  child: _PaymentMethodsList(data: report.paymentMethods),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SectionCard(
                  title: 'Order Types',
                  icon: Icons.receipt_long_outlined,
                  child: _OrderTypesList(data: report.orderTypes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Top-Selling Products',
            icon: Icons.trending_up,
            child: _TopProductsList(data: report.topProducts),
          ),
        ],
      ),
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  const _DateRangeSelector({
    required this.selectedRange,
    required this.onSelected,
  });

  final ReportsDateRange selectedRange;
  final ValueChanged<ReportsDateRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReportsDateRange>(
      segments: const [
        ButtonSegment(value: ReportsDateRange.today, label: Text('Today')),
        ButtonSegment(
          value: ReportsDateRange.yesterday,
          label: Text('Yesterday'),
        ),
        ButtonSegment(value: ReportsDateRange.last7Days, label: Text('7 Days')),
        ButtonSegment(
          value: ReportsDateRange.last30Days,
          label: Text('30 Days'),
        ),
      ],
      selected: {selectedRange},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onSelected(selection.first);
        }
      },
      showSelectedIcon: false,
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 1;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: columns == 3 ? 2.5 : 3.2,
          children: [
            _SummaryCard(
              icon: Icons.attach_money,
              title: 'Total Sales',
              value: _money(summary.totalSales),
            ),
            _SummaryCard(
              icon: Icons.receipt_long_outlined,
              title: 'Total Orders',
              value: summary.totalOrders.toString(),
            ),
            _SummaryCard(
              icon: Icons.shopping_cart_outlined,
              title: 'Average Order',
              value: _money(summary.averageOrderValue),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 30, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _HourlySalesChart extends StatelessWidget {
  const _HourlySalesChart({required this.data});

  final List<ReportHourlySalesPoint> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No sales data yet')),
      );
    }

    final maxValue = data
        .map((point) => point.total)
        .reduce((a, b) => a > b ? a : b);

    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    return SizedBox(
      height: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < data.length; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (data[index].total / safeMax).clamp(
                            0.03,
                            1.0,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 40,
                      child: Column(
                        children: [
                          if (index % 4 == 0)
                            Text(
                              data[index].hour.substring(0, 2),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            _money(data[index].total),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
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

class _SalesOverviewChart extends StatelessWidget {
  const _SalesOverviewChart({required this.data});

  final List<ReportSalesPoint> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No sales data yet')),
      );
    }

    final maxValue = data
        .map((point) => point.total)
        .reduce((a, b) => a > b ? a : b);

    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final dayFormat = DateFormat('dd MMM');

    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
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
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _money(point.total),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
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

class _PaymentMethodsList extends StatelessWidget {
  const _PaymentMethodsList({required this.data});

  final List<ReportPaymentMethod> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No payment data');
    }

    return Column(
      children: [
        for (final item in data)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments_outlined),
            title: Text(_label(item.method)),
            subtitle: Text('${item.count} payment(s)'),
            trailing: Text(
              _money(item.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

class _OrderTypesList extends StatelessWidget {
  const _OrderTypesList({required this.data});

  final List<ReportOrderType> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No order data');
    }

    return Column(
      children: [
        for (final item in data)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(_label(item.type)),
            subtitle: Text('${item.count} order(s)'),
            trailing: Text(
              _money(item.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

class _TopProductsList extends StatelessWidget {
  const _TopProductsList({required this.data});

  final List<ReportTopProduct> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('No product sales data');
    }

    return Column(
      children: [
        for (var index = 0; index < data.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 18, child: Text('${index + 1}')),
            title: Text(data[index].productName),
            subtitle: Text('${data[index].quantitySold} sold'),
            trailing: Text(
              _money(data[index].salesTotal),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            pos_ui.PrimaryButton.icon(
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

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}

String _label(String value) {
  switch (value) {
    case 'cash':
      return 'Cash';
    case 'card':
      return 'Card';
    case 'qr':
      return 'QR';
    case 'split':
      return 'Split';
    case 'dine_in':
      return 'Dine-in';
    case 'takeaway':
      return 'Takeaway';
    default:
      return value;
  }
}
