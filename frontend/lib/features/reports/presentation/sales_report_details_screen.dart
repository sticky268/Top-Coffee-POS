import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../data/sales_reports_repository.dart';
import '../domain/sales_report.dart';

class SalesReportDetailsScreen extends ConsumerStatefulWidget {
  const SalesReportDetailsScreen(
      {super.key,
      required this.query,
      required this.branchId,
      required this.kind,
      this.metric,
      this.method});
  final SalesReportQuery query;
  final int? branchId;
  final String kind;
  final String? metric;
  final String? method;
  @override
  ConsumerState<SalesReportDetailsScreen> createState() =>
      _SalesReportDetailsScreenState();
}

class _SalesReportDetailsScreenState
    extends ConsumerState<SalesReportDetailsScreen> {
  late Future<Map<String, dynamic>> request;
  int page = 1;
  @override
  void initState() {
    super.initState();
    request = load();
  }

  Future<Map<String, dynamic>> load() => ref
      .read(salesReportsRepositoryProvider)
      .details(widget.query, widget.branchId,
          kind: widget.kind,
          metric: widget.metric,
          method: widget.method,
          page: page);
  void refresh() => setState(() => request = load());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Report source records')),
        body: FutureBuilder<Map<String, dynamic>>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Could not load source records.'),
                  TextButton(onPressed: refresh, child: const Text('Retry')),
                ]));
              }
              final data = snapshot.requireData;
              final rows = SalesReport.maps(data['rows']);
              final total = data['total'] as int;
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text('$total source record(s) · page $page'),
                const Text(
                    'Amounts below match the selected metric or transaction. Average order shows its source order totals. Expand a record to review the breakdown.'),
                if (rows.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching records.')),
                for (final row in rows)
                  ExpansionTile(
                      title: Text(
                          'Order ${row['order_number'] ?? row['order_id']} · ${row['branch_name']}'),
                      subtitle: Text(
                          '${ReportAmount.parse(row['amount']).money}${row['method'] == null ? '' : ' · ${row['method']}'}'),
                      children: [
                        ListTile(
                            title: Text('Source order ID: ${row['order_id']}'),
                            subtitle: Text(
                                '${row['occurred_at_local'] ?? ''} · ${row['timezone']}${row['reason'] == null ? '' : '\n${row['reason']}'}')),
                        for (final field in const {
                          'order_total': 'Original order total',
                          'gross_sales': 'Gross',
                          'discounts': 'Discounts',
                          'tax': 'Tax',
                          'supplemental_sales': 'Additional charges'
                        }.entries)
                          if (row[field.key] != null)
                            ListTile(
                                title: Text(field.value),
                                subtitle: Text(
                                    ReportAmount.parse(row[field.key]).money)),
                      ]),
                Wrap(spacing: 12, children: [
                  OutlinedButton(
                      onPressed: page > 1
                          ? () {
                              page--;
                              refresh();
                            }
                          : null,
                      child: const Text('Previous')),
                  OutlinedButton(
                      onPressed: page * 50 < total
                          ? () {
                              page++;
                              refresh();
                            }
                          : null,
                      child: const Text('Next')),
                ]),
              ]);
            }),
      );
}
