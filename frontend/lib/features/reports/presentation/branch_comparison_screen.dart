import 'package:flutter/material.dart';
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
  const BranchComparisonScreen({super.key, required this.query});
  final SalesReportQuery query;
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
                      await next;
                    },
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      Text('All accessible branches',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          '${report.meta['date_from']} - ${report.meta['date_to']}'),
                      Text(
                          'Compared with ${report.meta['previous_from']} - ${report.meta['previous_to']}'),
                      Text(
                          'Cashier: ${report.meta['cashier_name'] ?? 'All sale cashiers'}\nCategory: ${report.meta['category_name'] ?? 'All historical categories'}'),
                      const Text(
                          'Each branch uses its own timezone. Dashboard branch selection does not limit this comparison.'),
                      TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.tune),
                          label: const Text('Change dates or filters')),
                      _metrics(report.summary, null),
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
                                    '${profitValue(row, 'revenue')} revenue\n${branchChange(row, 'revenue')}\n${row['timezone']}'),
                                childrenPadding: const EdgeInsets.all(12),
                                children: [
                              Text(
                                  'Revenue rank: ${row['revenue_rank'] ?? 'Not ranked'}; share: ${row['revenue_share_percent'] == null ? 'Unavailable' : '${row['revenue_share_percent']}%'}'),
                              _metrics(row, row['id'] as int),
                            ])),
                      ExpansionTile(
                          title: const Text('Accounting & comparison rules'),
                          childrenPadding: const EdgeInsets.all(12),
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
              onTap: () {
                _sources(branch);
              }),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gross margin'),
            subtitle: Text(
                '${row['margin_percent'] == null ? 'Unavailable' : '${row['margin_percent']}%'}\n${row['margin_change_points'] == null ? 'No comparable baseline' : '${row['margin_change_points']} percentage points vs previous'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _sources(branch);
            }),
      ]);
}
