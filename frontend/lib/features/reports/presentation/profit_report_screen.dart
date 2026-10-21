import 'package:flutter/material.dart';
import 'report_overview_widgets.dart';
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
  const ProfitReportScreen({
    super.key,
    required this.query,
    required this.branchId,
    this.onChangeFilters,
  });
  final SalesReportQuery query;
  final int? branchId;
  final VoidCallback? onChangeFilters;
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
        title: 'Profitability report',
        columnFlex: [4, 3, 3, 3],
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              mimeType: file.mimeType,
              name: file.name,
            ),
          ],
          fileNameOverrides: [file.name],
          subject: 'Top Coffee POS profitability report',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not export profitability. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _sources({int? product, String? category, int? branch}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfitSourceItemsScreen(
          query: widget.query,
          branchId: branch ?? widget.branchId,
          productId: product,
          category: category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Profit & performance')),
        body: PageContent(
          maxWidth: 1100,
          child: FutureBuilder<ProfitReport>(
            future: pending,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load profitability. Check the connection.',
                      ),
                      FilledButton(
                        onPressed: () => setState(() {
                          pending = _load();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final report = state.data;
              if (report == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return RefreshIndicator(
                onRefresh: () async {
                  final next = _load();
                  setState(() => pending = next);
                  try {
                    await next;
                  } catch (_) {
                    // FutureBuilder renders the error and Retry action.
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ReportHeader(
                      meta: report.meta,
                      scope: SalesReport.maps(report.meta['branches'])
                          .map((b) => '${b['name']}')
                          .join(', '),
                      filterLabel: 'Change report filters',
                      onChangeFilters: widget.onChangeFilters ??
                          () => Navigator.of(context).pop(),
                    ),
                    if (report.meta['category_id'] != null)
                      const Text(
                        'This category filter excludes older items with no category snapshot.',
                      ),
                    if (ReportAmount.parse(
                          report.summary['non_sales_refunds'],
                        ).cents >
                        0)
                      const Text(
                        'Refunds exceed recorded sale value. Review the separate non-sales refund amount in Sales, discounts & refunds.',
                      ),
                    if (report.summary['unknown_cost_lines'] != 0)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${report.summary['unknown_cost_lines']} line(s) have missing historical costs or an unverified restock. Total COGS, profit and margin are incomplete. Known costs are not the total.',
                          ),
                        ),
                      ),
                    ReportOverview(
                      primary: ReportMetricTile(
                        label: profitLabels['gross_profit']!,
                        value: profitValue(report.summary, 'gross_profit'),
                        prominent: true,
                        caption:
                            'Revenue less product costs. Operating expenses are excluded.',
                        onTap: _sources,
                      ),
                      metrics: [
                        for (final key in ['revenue', 'cogs', 'quantity'])
                          ReportMetricTile(
                              label: key == 'cogs'
                                  ? 'Product costs'
                                  : profitLabels[key]!,
                              value: profitValue(report.summary, key),
                              onTap: _sources),
                      ],
                    ),
                    ReportSection(title: 'Previous-period changes', children: [
                      for (final key in [
                        'revenue',
                        'cogs',
                        'gross_profit',
                        'quantity'
                      ])
                        ListTile(
                            title: Text(profitLabels[key]!),
                            subtitle: Text(_comparison(report.summary, key))),
                    ]),
                    ReportSection(
                      title: 'Sales, discounts & refunds',
                      children: [
                        for (final entry in profitLabels.entries.where(
                          (e) => ![
                            'revenue',
                            'cogs',
                            'gross_profit',
                            'quantity',
                          ].contains(e.key),
                        ))
                          ListTile(
                            title: Text(entry.value),
                            subtitle: Text(
                              '${profitValue(report.summary, entry.key)}\n${_comparison(report.summary, entry.key)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _sources,
                          ),
                      ],
                    ),
                    ReportSection(title: 'Gross margin', children: [
                      ListTile(
                          title: Text(report.summary['margin_percent'] == null
                              ? 'Unavailable'
                              : '${report.summary['margin_percent']}%'),
                          subtitle: Text(report
                                      .summary['margin_change_points'] ==
                                  null
                              ? 'No comparable margin baseline'
                              : '${report.summary['margin_change_points']} percentage points vs previous'),
                          onTap: _sources,
                          trailing: const Icon(Icons.chevron_right)),
                    ]),
                    ReportSection(
                      title: 'Accounting & cost coverage',
                      children: [
                        const Text(
                          'Uses the filters from Sales. Category here means individual sale-time items; older unknown categories appear separately.',
                        ),
                        Text(report.meta['basis'] as String),
                        Text(report.meta['cost_basis'] as String),
                        Text(
                          'Known COGS only: ${ReportCost.parse(report.summary['known_cogs']).money}. Restocked COGS reversed: ${ReportCost.parse(report.summary['reversed_cogs']).money}.',
                        ),
                        Text(
                          '${report.summary['legacy_category_lines']} line(s) have no historical category.',
                        ),
                      ],
                    ),
                    _group(
                      'Best sellers · units',
                      report.best,
                      (r) => _sources(product: r['id'] as int),
                    ),
                    _group(
                      'Slow sellers · units (sold at least once)',
                      report.slow,
                      (r) => _sources(product: r['id'] as int),
                    ),
                    ReportSection(
                      title: 'Popularity versus margin',
                      children: [
                        Text(
                          'Higher popularity: at least ${report.meta['popularity_threshold_units']} units (average per selling product, rounded up). Higher margin: at least ${report.meta['margin_threshold_percent'] ?? 'unavailable'}%, weighted across known-cost products with positive revenue. Refunded units remain sold units.',
                        ),
                        for (final row in report.products)
                          ListTile(
                            title: Text(row['name'] as String),
                            subtitle: Text(
                              '${performanceLabels[row['performance']] ?? row['performance']}\n${row['popularity_percent']}% of units · ${row['margin_percent'] ?? 'Unavailable'}% margin',
                            ),
                            onTap: () => _sources(product: row['id'] as int),
                          ),
                      ],
                    ),
                    _group(
                      'All products · profitability',
                      report.products,
                      (r) => _sources(product: r['id'] as int),
                    ),
                    _group(
                      'Categories · sale-time classification',
                      report.categories,
                      (r) => _sources(category: r['id'].toString()),
                    ),
                    _group(
                      'Branches · profitability',
                      report.branches,
                      (r) => _sources(branch: r['id'] as int),
                    ),
                    ReportSection(
                      title:
                          'Currently available, no sales · ${report.unsold.length}',
                      children: [
                        Text(report.meta['unsold_basis'] as String),
                        if (report.unsold.isEmpty)
                          const Text(
                            'No available products without sales in this selection.',
                          ),
                        for (final row in report.unsold)
                          ListTile(title: Text(row['name'] as String)),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final format in ReportExportFormat.values)
                          OutlinedButton.icon(
                            onPressed: exporting
                                ? null
                                : () => _export(report, format),
                            icon: const Icon(Icons.download),
                            label: Text(format.name.toUpperCase()),
                          ),
                      ],
                    ),
                    const Text(
                      'Offline sales appear after successful sync and refresh. Gross profit excludes operating expenses; this is not net profit.',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Widget _group(
    String title,
    List<Map<String, dynamic>> rows,
    void Function(Map<String, dynamic>) onTap,
  ) =>
      ReportSection(
        title: title,
        children: [
          if (rows.isEmpty)
            const ListTile(title: Text('No paid sales in this selection.')),
          for (final row in rows)
            ExpansionTile(
              key: PageStorageKey('profit-$title-${row['id']}'),
              title: Text(row['name'] as String),
              subtitle: Text(
                  '${row['quantity']} units · ${reportDisplayValue(profitValue(row, 'revenue'))} revenue\nProfit ${reportDisplayValue(profitValue(row, 'gross_profit'))}'),
              children: [
                for (final key in [
                  'revenue',
                  'cogs',
                  'gross_profit',
                  'quantity'
                ])
                  ListTile(
                      title: Text(profitLabels[key]!),
                      subtitle: Text(
                          '${profitValue(row, key)}\n${_comparison(row, key)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onTap(row)),
                ListTile(
                    title: const Text('Gross margin'),
                    subtitle: Text(
                        '${row['margin_percent'] == null ? 'Unavailable' : '${row['margin_percent']}%'}\nChange: ${row['margin_change_points'] ?? 'Unavailable'} percentage points')),
              ],
            ),
        ],
      );
}

String _comparison(Map<String, dynamic> row, String key) {
  final comparison = row['comparisons'][key] as Map?;
  if (comparison == null) return 'No complete cost comparison';
  final percent = comparison['percent'];
  return '${percent == null ? (comparison['status'] == 'new' ? 'New activity' : 'No change') : '$percent%'} vs previous · previous ${comparison['previous']}';
}

class ProfitSourceItemsScreen extends ConsumerStatefulWidget {
  const ProfitSourceItemsScreen({
    super.key,
    required this.query,
    required this.branchId,
    this.productId,
    this.category,
  });
  final SalesReportQuery query;
  final int? branchId;
  final int? productId;
  final String? category;
  @override
  ConsumerState<ProfitSourceItemsScreen> createState() =>
      _ProfitSourceItemsScreenState();
}

class _ProfitSourceItemsScreenState
    extends ConsumerState<ProfitSourceItemsScreen> {
  int page = 1;
  late Future<Map<String, dynamic>> pending;
  Future<Map<String, dynamic>> _load() =>
      ref.read(salesReportsRepositoryProvider).profitDetails(
            widget.query,
            widget.branchId,
            productId: widget.productId,
            category: widget.category,
            page: page,
          );
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
              // A changed future retains the preceding page's snapshot data.
              // Hide it, including its paging controls, until this request ends.
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: () => setState(() {
                      pending = _load();
                    }),
                    child: const Text('Retry source items'),
                  ),
                );
              }
              if (!state.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = state.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '${widget.query.dateFrom} – ${widget.query.dateTo} · Page ${data['page']} · ${data['total']} source lines',
                  ),
                  for (final row in SalesReport.maps(data['rows']))
                    ExpansionTile(
                      title: Text(
                        'Order ${row['order_number'] ?? row['order_id']} · ${row['name']}',
                      ),
                      subtitle: Text(
                        '${row['branch_name']} · ${row['occurred_at_local']}\nRevenue ${profitValue(row, 'revenue')} · profit ${profitValue(row, 'gross_profit')}',
                      ),
                      children: [
                        for (final key in profitLabels.keys)
                          ListTile(
                            title: Text(profitLabels[key]!),
                            subtitle: Text(profitValue(row, key)),
                          ),
                        ListTile(
                          title: Text(row['category_name'] as String),
                          subtitle: Text(
                            row['cost_reason']?.toString() ??
                                'Historical recipe cost recorded',
                          ),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: page <= 1
                            ? null
                            : () => setState(() {
                                  page--;
                                  pending = _load();
                                }),
                        child: const Text('Previous'),
                      ),
                      OutlinedButton(
                        onPressed: page * 50 >= (data['total'] as int)
                            ? null
                            : () => setState(() {
                                  page++;
                                  pending = _load();
                                }),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
}
