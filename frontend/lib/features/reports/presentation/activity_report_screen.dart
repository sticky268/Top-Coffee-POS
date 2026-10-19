import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/report_exporter.dart';
import '../data/sales_reports_repository.dart';
import '../domain/activity_report.dart';
import '../domain/sales_report.dart';

class ActivityReportScreen extends ConsumerStatefulWidget {
  const ActivityReportScreen({
    super.key,
    required this.query,
    required this.branchId,
  });
  final SalesReportQuery query;
  final int? branchId;
  @override
  ConsumerState<ActivityReportScreen> createState() =>
      _ActivityReportScreenState();
}

class _ActivityReportScreenState extends ConsumerState<ActivityReportScreen> {
  late Future<Map<String, dynamic>> request;
  bool exporting = false;
  String heatMetric = 'orders';
  Future<Map<String, dynamic>> load() => ref
      .read(salesReportsRepositoryProvider)
      .activity(widget.query, widget.branchId);
  @override
  void initState() {
    super.initState();
    request = load();
  }

  void sources({
    int? weekday,
    int? hour,
    int? cashier,
    String? cashierName,
    String kind = 'orders',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ActivitySources(
          query: widget.query,
          branchId: widget.branchId,
          weekday: weekday,
          hour: hour,
          cashier: cashier,
          cashierName: cashierName,
          kind: kind,
        ),
      ),
    );
  }

  String kind(String key) => key == 'voids'
      ? 'voids'
      : ['discounts', 'discounted_orders'].contains(key)
          ? 'discounts'
          : ['refunds', 'refunded_orders'].contains(key)
              ? 'refunds'
              : 'orders';

  Future<void> export(
    Map<String, dynamic> data,
    ReportExportFormat format,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final file = await ReportExporter.buildRows(
        activityReportRows(data, compact: format == ReportExportFormat.pdf),
        'top-coffee-activity-${data['meta']['date_from']}-${data['meta']['date_to']}',
        format,
        title: 'Time and cashier report',
        columnFlex: [5, 3, 3, 3],
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
          subject: 'Top Coffee POS time and cashier report',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not export. Retry or choose a smaller period.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Time & cashier performance')),
        body: PageContent(
          maxWidth: 1200,
          child: FutureBuilder<Map<String, dynamic>>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: () => setState(() {
                      request = load();
                    }),
                    child: const Text('Retry time and cashier report'),
                  ),
                );
              }
              final data = snapshot.requireData;
              final meta = data['meta'];
              final summary = Map<String, dynamic>.from(data['summary']);
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    request = load();
                  });
                  try {
                    await request;
                  } catch (_) {
                    // The FutureBuilder renders the error and Retry action.
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text(
                      SalesReport.maps(
                        meta['branches'],
                      )
                          .map((b) => '${b['name']} / ${b['timezone']}')
                          .join('\n'),
                    ),
                    Text(
                      '${meta['date_from']} - ${meta['date_to']}\nPrevious: ${meta['previous_from']} - ${meta['previous_to']}',
                    ),
                    Text(
                      'Cashier: ${meta['cashier_name'] ?? 'All'} / Category: ${meta['category_name'] ?? 'All'}',
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Change report filters'),
                    ),
                    for (final key in activityLabels.keys)
                      Card(
                        child: ListTile(
                          title: Text(activityLabels[key]!),
                          subtitle: Text(
                            '${activityValue(summary, key)}\n${activityChange(summary, key)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => sources(kind: kind(key)),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Weekday and hourly heatmap',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Local branch time. Swipe horizontally for all 24 hours; tap a cell for paid source orders. Repeated DST hours are combined.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final key in ['orders', 'net_sales'])
                          ChoiceChip(
                            label: Text(activityLabels[key]!),
                            selected: heatMetric == key,
                            onSelected: (_) => setState(() => heatMetric = key),
                          ),
                      ],
                    ),
                    const Text(
                      'Shade shows relative magnitude; negative net sales use red. New means no previous activity; - means no comparable baseline.',
                    ),
                    _heatmap(data),
                    const SizedBox(height: 20),
                    Text(
                      'Cashier performance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Grouped by original order cashier. Rates describe sale cohorts, not who authorised a refund or void.',
                    ),
                    Text(meta['flag_basis'] as String),
                    if ((data['cashiers'] as List).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No cashier activity in these periods.'),
                      ),
                    for (final row in SalesReport.maps(data['cashiers']))
                      ExpansionTile(
                        title: Text(row['name'] as String),
                        subtitle: Text(
                          '${activityValue(row, 'net_sales')} / ${row['orders']} paid orders\n${(row['flags'] as List).isEmpty ? 'No review flags' : 'Review: ${(row['flags'] as List).map((k) => activityRates[k]).join(', ')}'}',
                        ),
                        children: [
                          for (final key in activityLabels.keys)
                            ListTile(
                              title: Text(activityLabels[key]!),
                              subtitle: Text(
                                '${activityValue(row, key)}\n${activityChange(row, key)}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => sources(
                                cashier: row['id'] as int,
                                cashierName: row['name'] as String,
                                kind: kind(key),
                              ),
                            ),
                          for (final key in activityRates.keys)
                            ListTile(
                              title: Text(activityRates[key]!),
                              subtitle: Text(
                                '${activityRate(row['${key}_rate'], '%')} / previous ${activityRate(row['${key}_previous_rate'], '%')}\nChange: ${activityRate(row['${key}_change_points'], ' percentage points')}',
                              ),
                            ),
                        ],
                      ),
                    ExpansionTile(
                      title: const Text('Accounting and attribution'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(meta['basis'] as String),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final format in ReportExportFormat.values)
                          OutlinedButton(
                            onPressed:
                                exporting ? null : () => export(data, format),
                            child: Text('Export ${format.name.toUpperCase()}'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Widget _heatmap(Map<String, dynamic> data) {
    final cells = SalesReport.maps(data['cells']);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = (92 * scale).clamp(92.0, 184.0);
    final maximum = data['meta'][heatMetric == 'orders'
        ? 'heatmap_max_orders'
        : 'heatmap_max_net_cents'] as int;
    int magnitude(Map<String, dynamic> cell) => heatMetric == 'orders'
        ? cell['orders'] as int
        : ReportAmount.parse(cell['net_sales']).cents;
    final rowHeight = 72 * scale;
    final headerHeight = 48 * scale;
    Widget label(String text, double height, double labelWidth, {Key? key}) =>
        SizedBox(
            key: key,
            width: labelWidth,
            height: height,
            child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.all(4), child: Text(text))));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        label('Day', headerHeight, 56 * scale),
        for (var d = 1; d <= 7; d++)
          label(activityDays[d - 1], rowHeight, 56 * scale,
              key: ValueKey('activity-day-$d')),
      ]),
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      for (var h = 0; h < 24; h++)
                        label('${h.toString().padLeft(2, '0')}:00',
                            headerHeight, width),
                    ]),
                    for (var d = 1; d <= 7; d++)
                      Row(children: [
                        for (final cell
                            in cells.where((c) => c['weekday'] == d))
                          SizedBox(
                            width: width,
                            height: rowHeight,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Material(
                                color: (magnitude(cell) < 0
                                        ? Theme.of(context)
                                            .colorScheme
                                            .errorContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .primaryContainer)
                                    .withValues(
                                        alpha: 0.15 +
                                            0.85 *
                                                magnitude(cell).abs() /
                                                maximum),
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  key: ValueKey(
                                      'activity-cell-$d-${cell['hour']}'),
                                  onTap: () => sources(
                                      weekday: d, hour: cell['hour'] as int),
                                  child: Tooltip(
                                      message:
                                          '${activityPoint(cell)} / ${activityLabels[heatMetric]}: ${activityValue(cell, heatMetric)}',
                                      child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                    activityValue(
                                                        cell, heatMetric),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                                Text(
                                                    activityCellChange(
                                                        cell, heatMetric),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall),
                                              ]))),
                                ),
                              ),
                            ),
                          ),
                      ]),
                  ]))),
    ]);
  }
}

class _ActivitySources extends ConsumerStatefulWidget {
  const _ActivitySources({
    required this.query,
    required this.branchId,
    this.weekday,
    this.hour,
    this.cashier,
    this.cashierName,
    required this.kind,
  });
  final SalesReportQuery query;
  final int? branchId, weekday, hour, cashier;
  final String kind;
  final String? cashierName;
  @override
  ConsumerState<_ActivitySources> createState() => _ActivitySourcesState();
}

class _ActivitySourcesState extends ConsumerState<_ActivitySources> {
  int page = 1;
  late Future<Map<String, dynamic>> request;
  Future<Map<String, dynamic>> load() =>
      ref.read(salesReportsRepositoryProvider).activity(
            widget.query,
            widget.branchId,
            detail: true,
            page: page,
            weekday: widget.weekday,
            hour: widget.hour,
            cashier: widget.cashier,
            kind: widget.kind,
          );
  @override
  void initState() {
    super.initState();
    request = load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Activity source orders')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: request,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: FilledButton(
                  onPressed: () => setState(() {
                    request = load();
                  }),
                  child: const Text('Retry source orders'),
                ),
              );
            }
            final data = snapshot.requireData;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.query.dateFrom} - ${widget.query.dateTo} / ${widget.kind}\nPage ${data['page']} / ${data['total']} source orders',
                ),
                if (widget.weekday != null)
                  Text(
                    '${activityDays[widget.weekday! - 1]} ${widget.hour.toString().padLeft(2, '0')}:00 / local branch time',
                  ),
                if (widget.cashierName != null)
                  Text('Original order cashier: ${widget.cashierName}'),
                if ((data['rows'] as List).isEmpty)
                  const Text('No matching source orders.'),
                for (final row in SalesReport.maps(data['rows']))
                  ExpansionTile(
                    title:
                        Text('Order ${row['order_number'] ?? row['order_id']}'),
                    subtitle: Text(
                      '${row['branch_name']} / ${row['occurred_at_local']}',
                    ),
                    children: [
                      for (final key in activityLabels.keys)
                        ListTile(
                          title: Text(activityLabels[key]!),
                          subtitle: Text(activityValue(row, key)),
                        ),
                      ListTile(
                        title: const Text('Recorded refund / void actors'),
                        subtitle: Text(
                          (row['actors'] as List).isEmpty
                              ? 'No refund or void action recorded.'
                              : (row['actors'] as List).join(', '),
                        ),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: page <= 1
                          ? null
                          : () => setState(() {
                                page--;
                                request = load();
                              }),
                      child: const Text('Previous'),
                    ),
                    OutlinedButton(
                      onPressed: page * 50 >= (data['total'] as int)
                          ? null
                          : () => setState(() {
                                page++;
                                request = load();
                              }),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}
