import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/sales_reports_repository.dart';
import '../domain/sales_report.dart';
import 'report_overview_widgets.dart';
import 'sales_report_details_screen.dart';

class SalesTrends {
  const SalesTrends(this.today, this.week, this.month, this.months);
  final SalesReport today, week, month;
  final List<Map<String, dynamic>> months;

  static Future<SalesTrends> load(SalesReportsRepository repository,
      SalesReportQuery query, int? branchId) async {
    final today =
        await repository.load(query.periodSelection('today'), branchId);
    final date = DateTime.parse(today.meta['today'] as String);
    final years = {
      for (var i = 5; i >= 0; i--) DateTime(date.year, date.month - i).year
    };
    final reports = await Future.wait([
      repository.load(query.periodSelection('last7'), branchId),
      repository.load(query.periodSelection('this_month'), branchId),
      for (final year in years)
        repository.load(query.periodSelection('year', year: year), branchId),
    ]);
    final months = <Map<String, dynamic>>[];
    for (var i = 5; i >= 0; i--) {
      final month = DateTime(date.year, date.month - i);
      final matches = reports.skip(2).expand((r) => r.timeline).where((row) {
        final from = DateTime.parse(row['date_from'] as String);
        return from.year == month.year &&
            from.month == month.month &&
            row['upcoming'] != true;
      }).toList();
      if (matches.length != 1) {
        throw const FormatException('Incomplete monthly history');
      }
      months.add(matches.single);
    }
    return SalesTrends(today, reports[0], reports[1], months);
  }
}

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key, required this.query, required this.branchId});
  final SalesReportQuery query;
  final int? branchId;
  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  late Future<SalesTrends> pending;
  Future<SalesTrends> load() => SalesTrends.load(
      ref.read(salesReportsRepositoryProvider), widget.query, widget.branchId);
  @override
  void initState() {
    super.initState();
    pending = load();
  }

  void sources(String from, String to) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SalesReportDetailsScreen(
              query: widget.query.periodSelection('custom', from: from, to: to),
              branchId: widget.branchId,
              kind: 'orders',
              metric: 'total_sales')));
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Sales trends')),
        body: PageContent(
            maxWidth: 1100,
            child: FutureBuilder<SalesTrends>(
                future: pending,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: FilledButton(
                            onPressed: () => setState(() => pending = load()),
                            child: const Text('Retry trends')));
                  }
                  final data = snapshot.requireData;
                  Widget total(String title, SalesReport report) {
                    final c = report.comparisons['total_sales'] as Map;
                    final change = c['percent'] == null
                        ? (c['status'] == 'new'
                            ? 'New sales · previous period was zero'
                            : 'No comparable percentage')
                        : '${c['percent']}% vs previous period';
                    return ReportMetricTile(
                        label: title,
                        value: report.amount('total_sales').money,
                        prominent: title == 'Today',
                        caption:
                            '${report.summary['total_orders']} paid orders · $change',
                        onTap: () => sources(report.from, report.to));
                  }

                  return RefreshIndicator(
                      onRefresh: () async {
                        final next = load();
                        setState(() => pending = next);
                        try {
                          await next;
                        } catch (_) {/* Retry is shown above. */}
                      },
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const ReportIntro(
                                title: 'Your sales rhythm',
                                subtitle:
                                    'See the busy days and the bigger picture.',
                                icon: Icons.stacked_line_chart_rounded),
                            Text(SalesReport.maps(data.today.meta['branches'])
                                .map((b) => '${b['name']} · ${b['timezone']}')
                                .join('\n')),
                            if (widget.query.cashierId != null ||
                                widget.query.categoryId != null)
                              const Text(
                                  'Uses the selected cashier and category filters.'),
                            const SizedBox(height: 16),
                            total('Today', data.today),
                            SalesTrendChart(
                                title: 'Last 7 days',
                                rows: data.week.timeline,
                                onSelect: (row) => sources(
                                    row['date_from'] as String,
                                    row['date_to'] as String)),
                            total('This month', data.month),
                            SalesTrendChart(
                                title: 'Last 6 months',
                                rows: data.months,
                                monthly: true,
                                onSelect: (row) => sources(
                                    row['date_from'] as String,
                                    row['date_to'] as String)),
                            const ReportSection(
                                title: 'How to read these trends',
                                children: [
                                  Text(
                                      'Paid order totals include tax and precede later charges and refunds. The current month is still in progress. Calendar periods use the report’s branch timezones; combined branches use the server’s combined-date rules. Tap a bar for source orders.'),
                                  Text(
                                      'Only synced sales appear. These totals are sales, not profit.'),
                                ]),
                          ]));
                })),
      );
}

class SalesTrendChart extends StatelessWidget {
  const SalesTrendChart(
      {super.key,
      required this.title,
      required this.rows,
      required this.onSelect,
      this.monthly = false});
  final String title;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final bool monthly;
  @override
  Widget build(BuildContext context) {
    final amounts =
        rows.map((r) => ReportAmount.parse(r['total']).cents).toList();
    final maxValue = amounts.fold<int>(1, (a, b) => math.max(a, b.abs()));
    final scaled = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Card(
        margin: const EdgeInsets.only(bottom: 18),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Paid sales · tap a bar for details'),
                  const SizedBox(height: 20),
                  if (rows.isEmpty)
                    const Text('No sales history in this period.'),
                  if (rows.isNotEmpty)
                    LayoutBuilder(builder: (context, constraints) {
                      final width = math.max(
                          88.0 * scaled, constraints.maxWidth / rows.length);
                      return SingleChildScrollView(
                          key: PageStorageKey('trend-scroll-$title'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 0; i < rows.length; i++)
                                  SizedBox(
                                      width: width,
                                      child: Semantics(
                                          button: true,
                                          label:
                                              '${DateFormat(monthly ? 'MMMM yyyy' : 'dd MMM yyyy').format(DateTime.parse(rows[i]['date_from'] as String))}: ${reportDisplayValue(ReportAmount(amounts[i]).money)}',
                                          child: InkWell(
                                              key: ValueKey(
                                                  'trend-${rows[i]['date_from']}'),
                                              onTap: () => onSelect(rows[i]),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 5,
                                                      vertical: 8),
                                                  child: Column(children: [
                                                    SizedBox(
                                                        height: 30 * scaled,
                                                        child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            child: Text(
                                                                reportDisplayValue(
                                                                    ReportAmount(
                                                                            amounts[
                                                                                i])
                                                                        .money),
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelMedium))),
                                                    SizedBox(
                                                        height: 160,
                                                        child: Align(
                                                            alignment: Alignment
                                                                .bottomCenter,
                                                            child: Container(
                                                                width: math.min(
                                                                    42.0,
                                                                    width * .5),
                                                                height: math.max(
                                                                    3.0,
                                                                    amounts[i]
                                                                            .abs() /
                                                                        maxValue *
                                                                        160),
                                                                decoration: BoxDecoration(
                                                                    color: AppColors.semantic(
                                                                        context,
                                                                        amounts[i] <
                                                                                0
                                                                            ? AppColors
                                                                                .error
                                                                            : (i == rows.length - 1
                                                                                ? AppColors.warning
                                                                                : AppColors.ready)),
                                                                    borderRadius: BorderRadius.circular(8))))),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                        DateFormat(monthly
                                                                ? 'MMM yy'
                                                                : 'dd MMM')
                                                            .format(DateTime
                                                                .parse(rows[i][
                                                                        'date_from']
                                                                    as String)),
                                                        textAlign:
                                                            TextAlign.center),
                                                  ]))))),
                              ]));
                    }),
                ])));
  }
}
