import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../application/sales_reports_controller.dart';
import '../data/sales_reports_repository.dart';
import '../domain/sales_report.dart';
import 'reports_screen.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});
  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  SalesReportQuery query = const SalesReportQuery(period: 'last30');
  late Future<SalesReport> pending;
  bool monthly = false;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    pending = _load();
  }

  Future<SalesReport> _load() async => ref
      .read(salesReportsRepositoryProvider)
      .load(query, ref.read(currentBranchProvider)?.id);

  void _select(SalesReportQuery next) {
    setState(() {
      query = next;
      pending = _load();
    });
  }

  Future<void> _open(Map<String, dynamic> row) async {
    if (opening || row['upcoming'] == true) {
      return;
    }
    final branch = ref.read(currentBranchProvider)?.id;
    final date = DateTime.parse(row['date_from'] as String);
    final next = monthly
        ? query.periodSelection('month', year: date.year, month: date.month)
        : query.periodSelection(
            'custom',
            from: row['date_from'] as String,
            to: row['date_to'] as String,
          );
    setState(() {
      opening = true;
    });
    try {
      // The detail page owns its request/loading/error state and shared filters.
      final controller = ref.read(salesReportsControllerProvider.notifier);
      final selection = controller.select(next);
      if (!mounted || ref.read(currentBranchProvider)?.id != branch) {
        return;
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
      await selection;
    } finally {
      if (mounted) {
        setState(() {
          opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentBranchProvider, (previous, next) {
      if (previous?.id != next?.id) {
        _select(query.filters());
      }
    });
    return Scaffold(
      appBar: const PageAppBar(title: Text('Sales history')),
      body: PageContent(
        maxWidth: 1000,
        child: FutureBuilder<SalesReport>(
          future: pending,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load sales history. Check the connection and retry.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          _select(query);
                        },
                        child: const Text('Retry history'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final report = snapshot.data!;
            final today = DateTime.parse(report.meta['today'] as String);
            final year = query.year ?? today.year;
            final rows = [...report.timeline]
              ..sort(
                (a, b) => (b['date_from'] as String).compareTo(
                  a['date_from'] as String,
                ),
              );
            int? best;
            for (final row in rows) {
              if (row['upcoming'] != true) {
                final amount = ReportAmount.parse(row['total']).cents;
                if (amount > 0 && (best == null || amount > best)) {
                  best = amount;
                }
              }
            }
            return RefreshIndicator(
              onRefresh: () async {
                final next = _load();
                setState(() {
                  pending = next;
                });
                await next;
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Daily')),
                        ButtonSegment(value: true, label: Text('Monthly')),
                      ],
                      selected: {monthly},
                      onSelectionChanged: (selection) {
                        monthly = selection.single;
                        _select(
                          monthly
                              ? query.periodSelection('year', year: year)
                              : query.periodSelection('last30'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ref.watch(currentBranchProvider)?.name ??
                        'All accessible branches',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  if (monthly) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('history-year-$year'),
                      initialValue: year,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'History year',
                      ),
                      items: [
                        for (var y = today.year; y >= 2000; y--)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _select(query.periodSelection('year', year: value));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Every month of the selected year. Future months are marked upcoming.',
                    ),
                  ] else
                    Text(
                      'Last 30 days · ${DateFormat('d MMM').format(DateTime.parse(report.from))} – ${DateFormat('d MMM yyyy').format(DateTime.parse(report.to))}',
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paid order totals including tax, before refunds and additional charges. Tap a period for its full summary.',
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Cashier & category filters'),
                    subtitle: Text(
                      query.cashierId == null && query.categoryId == null
                          ? 'All cashiers · all categories'
                          : 'Filtered sales',
                    ),
                    children: [
                      _filter(
                        'Cashier',
                        query.cashierId,
                        SalesReport.maps(report.meta['cashiers']),
                        (id) => _select(
                          query.filters(
                            cashierId: id,
                            categoryId: query.categoryId,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _filter(
                        'Category',
                        query.categoryId,
                        SalesReport.maps(report.meta['categories']),
                        (id) => _select(
                          query.filters(
                            cashierId: query.cashierId,
                            categoryId: id,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Category selects whole orders. Item quantities include all their items, including items later refunded.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No periods available.'),
                    ),
                  for (final row in rows)
                    _HistoryRow(
                      key: ValueKey('history-${row['date_from']}'),
                      row: row,
                      monthly: monthly,
                      best:
                          best != null &&
                          row['upcoming'] != true &&
                          ReportAmount.parse(row['total']).cents == best,
                      onTap: opening || row['upcoming'] == true
                          ? null
                          : () {
                              _open(row);
                            },
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Dates follow each branch timezone. Offline sales appear after successful sync and refresh.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _filter(
    String label,
    int? value,
    List<Map<String, dynamic>> options,
    ValueChanged<int?> changed,
  ) => DropdownButtonFormField<int>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem<int>(
        value: null,
        child: Text(label == 'Cashier' ? 'All cashiers' : 'All categories'),
      ),
      for (final option in options)
        DropdownMenuItem(
          value: option['id'] as int,
          child: Text(
            option['name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: changed,
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.row,
    required this.monthly,
    required this.best,
    this.onTap,
  });
  final Map<String, dynamic> row;
  final bool monthly;
  final bool best;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final future = row['upcoming'] == true;
    final title = DateFormat(
      monthly ? 'MMMM yyyy' : 'd MMM yyyy',
    ).format(DateTime.parse(row['date_from'] as String));
    final amount = future ? 'Upcoming' : ReportAmount.parse(row['total']).money;
    final subtitle = future
        ? 'No sales period yet'
        : row['orders'] == null || row['items'] == null
        ? 'Paid orders'
        : '${row['orders']} paid orders · ${row['items']} items';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      color: best ? scheme.tertiary.withValues(alpha: .08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: best ? scheme.tertiary : scheme.outlineVariant,
          width: best ? 1.5 : .6,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 290 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (best)
                        Tooltip(
                          message: 'Highest order total in this list',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.tertiary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Top',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onTertiary),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final total = ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: stacked
                      ? constraints.maxWidth
                      : constraints.maxWidth * .48,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        amount,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: future
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      future ? Icons.schedule : Icons.chevron_right,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [details, const SizedBox(height: 10), total],
                    )
                  : Row(
                      children: [
                        Expanded(child: details),
                        const SizedBox(width: 16),
                        total,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}
