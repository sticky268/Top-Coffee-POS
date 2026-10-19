import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/report_exporter.dart';
import '../data/sales_reports_repository.dart';
import '../domain/profit_report.dart';
import '../domain/sales_report.dart';

const performanceLabels = {
  'star': 'Star · popular, higher margin',
  'volume': 'Volume · popular, lower margin',
  'opportunity': 'Opportunity · quieter, higher margin',
  'review': 'Review · quieter, lower margin',
  'cost_missing': 'Cost incomplete',
  'no_net_revenue': 'No positive net revenue',
  'no_sales': 'No sales this period',
};

class ProfitReportScreen extends ConsumerStatefulWidget {
  const ProfitReportScreen(
      {super.key, required this.query, required this.branchId});
  final SalesReportQuery query;
  final int? branchId;
  @override
  ConsumerState<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends ConsumerState<ProfitReportScreen> {
  late Future<ProfitReport> pending;
  bool exporting = false;
  @override
  void initState() {
    super.initState();
    pending = _load();
  }

  Future<ProfitReport> _load() => ref
      .read(salesReportsRepositoryProvider)
      .profit(widget.query, widget.branchId);
  Future<void> _export(ProfitReport report, ReportExportFormat format) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final file = await ReportExporter.buildRows(
          format == ReportExportFormat.pdf
              ? profitReportPdfRows(report)
              : profitReportRows(report),
          'top-coffee-profit-${report.meta['date_from']}-${report.meta['date_to']}',
          format,
          title: 'Profitability report');
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)
          ],
          fileNameOverrides: [
            file.name
          ],
          subject: 'Top Coffee POS profitability report',
          sharePositionOrigin: origin));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not export profitability. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _sources({int? product, String? category, int? branch}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _ProfitSources(
            query: widget.query,
            branchId: branch ?? widget.branchId,
            productId: product,
            category: category)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: const PageAppBar(title: Text('Profit & performance')),
      body: PageContent(
          maxWidth: 1100,
          child: FutureBuilder<ProfitReport>(
              future: pending,
              builder: (context, state) {
                if (state.hasError) {
                  return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Could not load profitability. Check the connection.'),
                    FilledButton(
                        onPressed: () => setState(() => pending = _load()),
                        child: const Text('Retry'))
                  ]));
                }
                final report = state.data;
                if (report == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RefreshIndicator(
                    onRefresh: () async {
                      final next = _load();
                      setState(() => pending = next);
                      await next;
                    },
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      Text(SalesReport.maps(report.meta['branches'])
                          .map((b) => '${b['name']} · ${b['timezone']}')
                          .join('\n')),
                      Text(
                          '${report.meta['date_from']} – ${report.meta['date_to']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          'Compared with ${report.meta['previous_from']} – ${report.meta['previous_to']}'),
                      const Text(
                          'Uses the date, branch, cashier and category filters from Sales. Go back to change the selection. Category here means individual sale-time items; older unknown categories appear separately.'),
                      if (report.summary['unknown_cost_lines'] != 0)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                    '${report.summary['unknown_cost_lines']} line(s) have missing historical costs or an unverified restock. Total COGS, profit and margin are incomplete. Known costs are not the total.'))),
                      for (final metric in profitLabels.entries)
                        Card(
                            child: ListTile(
                                title: Text(metric.value),
                                subtitle: Text(
                                    '${profitValue(report.summary, metric.key)}\n${_comparison(report.summary, metric.key)}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _sources)),
                      Card(
                          child: ListTile(
                              title: const Text('Gross margin'),
                              subtitle: Text(
                                  '${report.summary['margin_percent'] == null ? 'Unavailable' : '${report.summary['margin_percent']}%'}\n${report.summary['margin_change_points'] == null ? 'No comparable margin baseline' : '${report.summary['margin_change_points']} percentage points vs previous'}'),
                              onTap: _sources,
                              trailing: const Icon(Icons.chevron_right))),
                      ExpansionTile(
                          title: const Text('Accounting & cost coverage'),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                            Text(report.meta['basis'] as String),
                            Text(report.meta['cost_basis'] as String),
                            Text(
                                'Known COGS only: ${ReportCost.parse(report.summary['known_cogs']).money}. Restocked COGS reversed: ${ReportCost.parse(report.summary['reversed_cogs']).money}.'),
                            Text(
                                '${report.summary['legacy_category_lines']} line(s) have no historical category.')
                          ]),
                      _group('Best sellers · units', report.best,
                          (r) => _sources(product: r['id'] as int)),
                      _group(
                          'Slow sellers · units (sold at least once)',
                          report.slow,
                          (r) => _sources(product: r['id'] as int)),
                      ExpansionTile(
                          title: const Text('Popularity versus margin'),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            Text(
                                'Higher popularity: at least ${report.meta['popularity_threshold_units']} units, the average per selling product. Higher margin: at least ${report.meta['margin_threshold_percent'] ?? 'unavailable'}%, weighted across known-cost products with positive revenue. Refunded units remain sold units.'),
                            for (final row in report.products)
                              ListTile(
                                  title: Text(row['name'] as String),
                                  subtitle: Text(
                                      '${performanceLabels[row['performance']] ?? row['performance']}\n${row['popularity_percent']}% of units · ${row['margin_percent'] ?? 'Unavailable'}% margin'),
                                  onTap: () =>
                                      _sources(product: row['id'] as int))
                          ]),
                      _group('All products · profitability', report.products,
                          (r) => _sources(product: r['id'] as int)),
                      _group(
                          'Categories · sale-time classification',
                          report.categories,
                          (r) => _sources(category: r['id'].toString())),
                      _group('Branches · profitability', report.branches,
                          (r) => _sources(branch: r['id'] as int)),
                      ExpansionTile(
                          title: Text(
                              'Currently available, no sales · ${report.unsold.length}'),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                            Text(report.meta['unsold_basis'] as String),
                            if (report.unsold.isEmpty)
                              const Text(
                                  'No available products without sales in this selection.'),
                            for (final row in report.unsold)
                              ListTile(title: Text(row['name'] as String))
                          ]),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final format in ReportExportFormat.values)
                          OutlinedButton.icon(
                              onPressed: exporting
                                  ? null
                                  : () => _export(report, format),
                              icon: const Icon(Icons.download),
                              label: Text(format.name.toUpperCase()))
                      ]),
                      const Text(
                          'Offline sales appear after successful sync and refresh. Gross profit excludes operating expenses; this is not net profit.'),
                    ]));
              })));

  Widget _group(String title, List<Map<String, dynamic>> rows,
          void Function(Map<String, dynamic>) onTap) =>
      ExpansionTile(
          title: Text(title),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            if (rows.isEmpty)
              const ListTile(title: Text('No paid sales in this selection.')),
            for (final row in rows)
              ListTile(
                  title: Text(row['name'] as String),
                  subtitle: Text(
                      '${row['quantity']} units · revenue ${profitValue(row, 'revenue')}\nCOGS ${profitValue(row, 'cogs')} · profit ${profitValue(row, 'gross_profit')}\nMargin ${row['margin_percent'] ?? 'Unavailable'}% · ${_comparison(row, 'revenue')}'),
                  onTap: () => onTap(row),
                  trailing: const Icon(Icons.chevron_right))
          ]);
}

String _comparison(Map<String, dynamic> row, String key) {
  final comparison = row['comparisons'][key] as Map?;
  if (comparison == null) return 'No complete cost comparison';
  final percent = comparison['percent'];
  return '${percent == null ? (comparison['status'] == 'new' ? 'New activity' : 'No change') : '$percent%'} vs previous · previous ${comparison['previous']}';
}

class _ProfitSources extends ConsumerStatefulWidget {
  const _ProfitSources(
      {required this.query,
      required this.branchId,
      this.productId,
      this.category});
  final SalesReportQuery query;
  final int? branchId;
  final int? productId;
  final String? category;
  @override
  ConsumerState<_ProfitSources> createState() => _ProfitSourcesState();
}

class _ProfitSourcesState extends ConsumerState<_ProfitSources> {
  int page = 1;
  late Future<Map<String, dynamic>> pending;
  Future<Map<String, dynamic>> _load() => ref
      .read(salesReportsRepositoryProvider)
      .profitDetails(widget.query, widget.branchId,
          productId: widget.productId, category: widget.category, page: page);
  @override
  void initState() {
    super.initState();
    pending = _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: const PageAppBar(title: Text('Profit source items')),
      body: PageContent(
          maxWidth: 1000,
          child: FutureBuilder<Map<String, dynamic>>(
              future: pending,
              builder: (context, state) {
                if (state.hasError) {
                  return Center(
                      child: FilledButton(
                          onPressed: () => setState(() => pending = _load()),
                          child: const Text('Retry source items')));
                }
                if (!state.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = state.data!;
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                      '${widget.query.dateFrom} – ${widget.query.dateTo} · Page $page · ${data['total']} source lines'),
                  for (final row in SalesReport.maps(data['rows']))
                    ExpansionTile(
                        title: Text(
                            'Order ${row['order_number'] ?? row['order_id']} · ${row['name']}'),
                        subtitle: Text(
                            '${row['branch_name']} · ${row['occurred_at_local']}\nRevenue ${profitValue(row, 'revenue')} · profit ${profitValue(row, 'gross_profit')}'),
                        children: [
                          for (final key in profitLabels.keys)
                            ListTile(
                                title: Text(profitLabels[key]!),
                                trailing: Text(profitValue(row, key))),
                          ListTile(
                              title: Text(row['category_name'] as String),
                              subtitle: Text(row['cost_reason']?.toString() ??
                                  'Historical recipe cost recorded'))
                        ]),
                  Wrap(spacing: 12, children: [
                    OutlinedButton(
                        onPressed: page <= 1
                            ? null
                            : () => setState(() {
                                  page--;
                                  pending = _load();
                                }),
                        child: const Text('Previous')),
                    OutlinedButton(
                        onPressed: page * 50 >= (data['total'] as int)
                            ? null
                            : () => setState(() {
                                  page++;
                                  pending = _load();
                                }),
                        child: const Text('Next'))
                  ])
                ]);
              })));
}
