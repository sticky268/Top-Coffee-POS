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
      appBar: const PageAppBar(title: Text('Sale Reports'), centerTitle: true),
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
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final mode in [false, true])
                            ChoiceChip(
                              label: Text(mode ? 'Monthly' : 'Daily'),
                              selected: monthly == mode,
                              showCheckmark: false,
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              selectedColor: const Color(0xff2563eb),
                              backgroundColor: Colors.transparent,
                              labelStyle: TextStyle(
                                color: monthly == mode
                                    ? Colors.white
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              onSelected: (_) {
                                if (monthly == mode) return;
                                monthly = mode;
                                _select(
                                  monthly
                                      ? query.periodSelection(
                                          'year',
                                          year: year,
                                        )
                                      : query.periodSelection('last30'),
                                );
                              },
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Sales filters',
                        onPressed: () => _showFilters(report),
                        icon: Badge(
                          isLabelVisible:
                              query.cashierId != null ||
                              query.categoryId != null,
                          child: const Icon(Icons.filter_list),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ref.watch(currentBranchProvider)?.name ??
                        'All accessible branches',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                    const SizedBox(height: 12),
                    Text('Your monthly sales for $year'),
                  ] else
                    Text(
                      'Your sales from the last ${DateTime.parse('${report.to}T00:00:00Z').difference(DateTime.parse('${report.from}T00:00:00Z')).inDays + 1} days',
                    ),
                  if (query.cashierId != null || query.categoryId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Filtered sales',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  const SizedBox(height: 12),
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

  Future<void> _showFilters(SalesReport report) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sales filters',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _filter(
              'Cashier',
              query.cashierId,
              SalesReport.maps(report.meta['cashiers']),
              (id) {
                Navigator.of(sheet).pop();
                _select(
                  query.filters(cashierId: id, categoryId: query.categoryId),
                );
              },
            ),
            const SizedBox(height: 16),
            _filter(
              'Category',
              query.categoryId,
              SalesReport.maps(report.meta['categories']),
              (id) {
                Navigator.of(sheet).pop();
                _select(
                  query.filters(cashierId: query.cashierId, categoryId: id),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Paid order totals include tax, before refunds and additional charges. Category filters select whole orders; item counts include all their items, including items later refunded.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap a day or month to open its full sales summary. Future months are marked upcoming.',
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                _select(query.filters());
              },
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    ),
  );

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topColor = dark ? const Color(0xff6ee7b7) : const Color(0xff168565);
    final amountColor = dark
        ? const Color(0xffc4b5fd)
        : const Color(0xff5b3db2);
    final future = row['upcoming'] == true;
    final title = DateFormat(
      monthly ? 'MMMM yyyy' : 'd MMM yyyy',
    ).format(DateTime.parse(row['date_from'] as String));
    final amount = future
        ? 'Upcoming'
        : ReportAmount.parse(row['total']).money.replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+\.)'),
            (match) => '${match[1]},',
          );
    final subtitle = future
        ? 'No sales period yet'
        : row['orders'] == null || row['items'] == null
        ? 'Paid orders'
        : '${row['orders']} ${row['orders'] == 1 ? 'Sale' : 'Sales'} · ${row['items']} ${row['items'] == 1 ? 'Item' : 'Items'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      color: best ? topColor.withValues(alpha: .08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: best ? topColor : scheme.outlineVariant,
          width: best ? 1.5 : .6,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              color: topColor,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Top',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: dark
                                        ? const Color(0xff102a20)
                                        : Colors.white,
                                  ),
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
                                  : amountColor,
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
