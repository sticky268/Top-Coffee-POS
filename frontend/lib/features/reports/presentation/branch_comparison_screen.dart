import 'package:flutter/material.dart';
import 'report_overview_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/report_exporter.dart';
import '../data/sales_reports_repository.dart';
import '../domain/branch_comparison.dart';
import '../domain/profit_report.dart';
import '../domain/sales_report.dart';
import 'profit_report_screen.dart';

class BranchComparisonScreen extends ConsumerStatefulWidget {
  const BranchComparisonScreen(
      {super.key, required this.query, this.onChangeFilters});
  final SalesReportQuery query;
  final VoidCallback? onChangeFilters;
  @override
  ConsumerState<BranchComparisonScreen> createState() =>
      _BranchComparisonScreenState();
}

class _BranchComparisonScreenState
    extends ConsumerState<BranchComparisonScreen> {
  late Future<BranchComparison> pending;
  bool exporting = false;
  @override
  void initState() {
    super.initState();
    pending = _load();
  }

  // Deliberately compare all authorised branches, independent of dashboard scope.
  Future<BranchComparison> _load() async => BranchComparison(await ref
      .read(salesReportsRepositoryProvider)
      .branchComparison(widget.query, null));

  void _sources(int? branch) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ProfitSourceItemsScreen(query: widget.query, branchId: branch)));
  }

  Future<void> _export(
      BranchComparison report, ReportExportFormat format) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      exporting = true;
    });
    try {
      final file = await ReportExporter.buildRows(
          branchComparisonRows(report, pdf: format == ReportExportFormat.pdf),
          'top-coffee-branches-${report.meta['date_from']}-${report.meta['date_to']}',
          format,
          title: 'Branch comparison',
          columnFlex: [4, 3, 3, 3],
          notes: format == ReportExportFormat.pdf ? report.basis : null);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)
          ],
          fileNameOverrides: [
            file.name
          ],
          subject: 'Top Coffee POS branch comparison',
          sharePositionOrigin: origin));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not export branch comparison. Please retry.')));
      }
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: const PageAppBar(title: Text('Branch comparison')),
      body: PageContent(
          maxWidth: 1000,
          child: FutureBuilder<BranchComparison>(
              future: pending,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Could not load branch comparison. Check the connection.'),
                    FilledButton(
                        onPressed: () {
                          setState(() {
                            pending = _load();
                          });
                        },
                        child: const Text('Retry')),
                  ]));
                }
                final report = snapshot.data!;
                return RefreshIndicator(
                    onRefresh: () async {
                      final next = _load();
                      setState(() {
                        pending = next;
                      });
                      try {
                        await next;
                      } catch (_) {
                        // FutureBuilder renders the error and Retry action.
                      }
                    },
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      ReportHeader(
                        meta: report.meta,
                        scope: 'All accessible branches',
                        filterLabel: 'Change dates or filters',
                        onChangeFilters: widget.onChangeFilters ??
                            () => Navigator.of(context).pop(),
                        notes: const [
                          Text(
                              'Each branch uses its own timezone. Dashboard branch selection does not limit this comparison.')
                        ],
                      ),
                      if (report.summary['unknown_cost_lines'] != 0)
                        Text(
                            '${report.summary['unknown_cost_lines']} line(s) have incomplete historical costs. Profit and margin are unavailable.'),
                      ReportOverview(
                        primary: ReportMetricTile(
                            label: profitLabels['revenue']!,
                            value: profitValue(report.summary, 'revenue'),
                            prominent: true,
                            caption:
                                'Combined revenue across accessible branches.',
                            onTap: report.summary['lines'] == 0
                                ? null
                                : () => _sources(null)),
                        metrics: [
                          for (final key in [
                            'gross_profit',
                            'cogs',
                            'quantity'
                          ])
                            ReportMetricTile(
                                label: key == 'cogs'
                                    ? 'Product costs'
                                    : profitLabels[key]!,
                                value: profitValue(report.summary, key),
                                onTap: report.summary['lines'] == 0
                                    ? null
                                    : () => _sources(null)),
                        ],
                      ),
                      ReportSection(
                          title: 'Totals & previous-period changes',
                          children: [_metrics(report.summary, null)]),
                      const SizedBox(height: 16),
                      Text('Branches by revenue',
                          style: Theme.of(context).textTheme.titleLarge),
                      if (report.branches.isEmpty)
                        const Text('No accessible branches.'),
                      if (report.branches.length == 1)
                        const Text(
                            'Only one branch is accessible to this account.'),
                      for (final row in report.branches)
                        Card(
                            child: ExpansionTile(
                                key: ValueKey('branch-${row['id']}'),
                                title: Text(row['name'] as String),
                                subtitle: Text(
                                    '${reportDisplayValue(profitValue(row, 'revenue'))} revenue · ${row['revenue_share_percent'] == null ? 'Share unavailable' : '${row['revenue_share_percent']}% of total'}'),
                                childrenPadding: const EdgeInsets.all(12),
                                children: [
                              Text('${row['timezone']}'),
                              Text(
                                  'Revenue rank: ${row['revenue_rank'] ?? 'Not ranked'}; share: ${row['revenue_share_percent'] == null ? 'Unavailable' : '${row['revenue_share_percent']}%'}'),
                              _metrics(row, row['id'] as int),
                            ])),
                      ReportSection(
                          title: 'Accounting & comparison rules',
                          children: [Text(report.basis)]),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final format in ReportExportFormat.values)
                          OutlinedButton.icon(
                              onPressed: exporting
                                  ? null
                                  : () {
                                      _export(report, format);
                                    },
                              icon: const Icon(Icons.download),
                              label: Text(format.name.toUpperCase()))
                      ]),
                    ]));
              })));

  Widget _metrics(Map<String, dynamic> row, int? branch) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (row['unknown_cost_lines'] != 0)
          Text(
              '${row['unknown_cost_lines']} line(s) have incomplete historical costs. Profit and margin are unavailable.'),
        for (final key in ['revenue', 'cogs', 'gross_profit', 'quantity'])
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(profitLabels[key]!),
              subtitle:
                  Text('${profitValue(row, key)}\n${branchChange(row, key)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: row['lines'] == 0
                  ? null
                  : () {
                      _sources(branch);
                    }),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gross margin'),
            subtitle: Text(
                '${row['margin_percent'] == null ? 'Unavailable' : '${row['margin_percent']}%'}\n${row['margin_change_points'] == null ? 'No comparable baseline' : '${row['margin_change_points']} percentage points vs previous'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: row['lines'] == 0
                ? null
                : () {
                    _sources(branch);
                  }),
      ]);
}
