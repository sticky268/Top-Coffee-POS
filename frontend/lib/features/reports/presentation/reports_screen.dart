import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../application/sales_reports_controller.dart';
import '../data/report_exporter.dart';
import '../domain/sales_report.dart';
import 'sales_report_details_screen.dart';

const reportMetricLabels = {
  'net_sales': 'Net sales',
  'gross_sales': 'Gross sales',
  'discounts': 'Discounts',
  'refunds': 'Refunds',
  'tax': 'Tax',
  'total_sales': 'Order totals',
  'supplemental_sales': 'Additional charges',
  'total_orders': 'Paid orders',
  'average_order_value': 'Average order',
};

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesReportsControllerProvider);
    final controller = ref.read(salesReportsControllerProvider.notifier);
    return Scaffold(
      appBar: const PageAppBar(title: Text('Sales summary')),
      body: PageContent(
          maxWidth: 1200,
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: controller.refresh,
                          child: const Text('Retry')),
                    ]))),
            data: (report) => _ReportContent(report: report),
          )),
    );
  }
}

class _ReportContent extends ConsumerWidget {
  const _ReportContent({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(salesReportsControllerProvider.notifier);
    final query = controller.query;
    final branches = SalesReport.maps(report.meta['branches']);
    final today = DateTime.parse(report.meta['today'] as String);
    final year = query.year ?? DateTime.parse(report.from).year;
    final hasCategory = query.categoryId != null;
    final timeline = _Section(
        title: query.period == 'year'
            ? 'Monthly history · $year'
            : 'Daily breakdown',
        children: [
          const Text(
              'Paid order totals, including tax, before later adjustments. Tap a period to open it.'),
          for (final row in report.timeline)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(query.period == 'year'
                    ? DateFormat('MMMM')
                        .format(DateTime.parse(row['date_from'] as String))
                    : _date(row['date_from'] as String)),
                subtitle: Text(row['upcoming'] == true
                    ? 'Upcoming month'
                    : ReportAmount.parse(row['total']).money),
                trailing: Icon(row['upcoming'] == true
                    ? Icons.schedule
                    : Icons.chevron_right),
                onTap: row['upcoming'] == true
                    ? null
                    : () {
                        final date = DateTime.parse(row['date_from'] as String);
                        if (query.period == 'year') {
                          controller.select(query.periodSelection('month',
                              year: date.year, month: date.month));
                        } else if (row['date_from'] == report.from &&
                            report.from == report.to) {
                          _details(context, ref, kind: 'orders');
                        } else {
                          controller.select(query.periodSelection('custom',
                              from: row['date_from'] as String,
                              to: row['date_to'] as String));
                        }
                      }),
        ]);
    return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
                branches.isEmpty
                    ? 'No accessible branches'
                    : branches
                        .map((b) => '${b['name']} · ${b['timezone']}')
                        .join('\n'),
                style: Theme.of(context).textTheme.titleSmall),
            if (branches.length > 1)
              const Text(
                  'Combined presets use UTC calendar dates; each branch contributes its own local day.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final option in const {
                'today': 'Today',
                'yesterday': 'Yesterday',
                'week': 'This Week',
                'this_month': 'This Month',
                'last_month': 'Last Month',
                'last7': '7 Days',
                'last30': '30 Days'
              }.entries)
                ChoiceChip(
                    label: Text(option.value),
                    selected: query.period == option.key,
                    onSelected: (_) =>
                        controller.select(query.periodSelection(option.key))),
              ActionChip(
                  label: const Text('Choose dates'),
                  avatar: const Icon(Icons.date_range, size: 18),
                  onPressed: () async {
                    final dates = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100, 12, 31),
                        initialDateRange: DateTimeRange(
                            start: DateTime.parse(report.from),
                            end: DateTime.parse(report.to)));
                    if (dates == null || !context.mounted) return;
                    if (dates.end.difference(dates.start).inDays >= 366) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Choose at most 366 days.')));
                      return;
                    }
                    await controller.select(query.periodSelection('custom',
                        from: DateFormat('yyyy-MM-dd').format(dates.start),
                        to: DateFormat('yyyy-MM-dd').format(dates.end)));
                  }),
            ]),
            const SizedBox(height: 12),
            Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<int>(
                          initialValue: year,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'History year'),
                          items: [
                            for (var y = today.year > year ? today.year : year;
                                y >= 2000;
                                y--)
                              DropdownMenuItem(value: y, child: Text('$y'))
                          ],
                          onChanged: (y) {
                            if (y != null) {
                              controller.select(
                                  query.periodSelection('year', year: y));
                            }
                          })),
                  OutlinedButton.icon(
                      onPressed: () => controller
                          .select(query.periodSelection('year', year: year)),
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Browse all 12 months')),
                ]),
            const SizedBox(height: 12),
            _ReportFilter(
                label: 'Cashier',
                value: query.cashierId,
                options: SalesReport.maps(report.meta['cashiers']),
                onChanged: (id) => controller.select(query.filters(
                    cashierId: id, categoryId: query.categoryId))),
            const SizedBox(height: 8),
            _ReportFilter(
                label: 'Category — orders containing',
                value: query.categoryId,
                options: SalesReport.maps(report.meta['categories']),
                onChanged: (id) => controller.select(
                    query.filters(cashierId: query.cashierId, categoryId: id))),
            const SizedBox(height: 16),
            Text('${_date(report.from)} – ${_date(report.to)}',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                'Compared with ${_date(report.meta['previous_from'] as String)} – ${_date(report.meta['previous_to'] as String)}'),
            if (hasCategory)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(report.meta['category_basis'] as String)),
            const SizedBox(height: 12),
              if (query.period == 'year') timeline,
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : (constraints.maxWidth >= 360 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 20
                      ? 2
                      : 1);
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final metric in reportMetricLabels.entries)
                  SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 12) / columns,
                      child: _MetricCard(
                          label: metric.value,
                          value: metric.key == 'total_orders'
                              ? '${report.summary[metric.key]}'
                              : report.amount(metric.key).money,
                          comparison: Map<String, dynamic>.from(
                              report.comparisons[metric.key] as Map),
                          isMoney: metric.key != 'total_orders',
                          onTap: () => _details(context, ref,
                              metric: metric.key,
                              kind: metric.key == 'refunds'
                                  ? 'refunds'
                                  : 'orders'))),
              ]);
            }),
            const SizedBox(height: 8),
            Text(report.meta['sales_basis'] as String),
            const Text(
                'Gross − discounts + tax = order totals. Net sales includes tax and additional charges, less refunds.'),
            if (report.summary['excluded_orders'] != 0)
              TextButton(
                  onPressed: () => _details(context, ref, kind: 'excluded'),
                  child: Text(
                      '${report.summary['excluded_orders']} completed order(s) excluded: payment reconciliation needed')),
            if (report.amount('payment_difference').cents != 0)
              Text(
                  'Payment reconciliation difference: ${report.amount('payment_difference').money}. Review source payments.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            if (query.period != 'year') timeline,
            if (report.hourlySales.isNotEmpty)
              _Section(title: 'Hourly sales', children: [
                const Text(
                    'Branch-local hour · paid order totals before later adjustments.'),
                ExpansionTile(
                    title: const Text('Show hourly breakdown'),
                    children: [
                      for (final row in report.hourlySales)
                        _AmountLine(row['hour'] as String, row['total']),
                    ]),
              ]),
            _Section(title: 'Top-Selling Products', children: [
              const Text(
                  'Quantity ranking. Sales before order discounts; names follow saved sale records.'),
              if (report.topProducts.isEmpty)
                const Text('No product sales in this selection.'),
              for (final row in report.topProducts)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['product_name'] as String),
                    subtitle: Text(
                        '${row['quantity']} sold · ${_money(row['total'])}')),
            ]),
            _Section(title: 'Order types', children: [
              for (final row in report.orderTypes)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${row['type']} · ${row['count']} orders'),
                    subtitle: Text(_money(row['total']))),
              if (report.orderTypes.isEmpty)
                const Text('No paid orders in this selection.'),
            ]),
            _Section(title: 'Payments on selected sales', children: [
              if (report.paymentMethods.isEmpty)
                const Text('No settled payments in this selection.'),
              for (final method in report.paymentMethods)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${_method(method['method'])} · ${method['count']} payments'),
                    subtitle: Text(
                        'Collected ${_money(method['collected'])}\nRefunds ${_money(method['refunds'])}\nNet ${_money(method['net'])}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _details(context, ref,
                        kind: 'payments', method: method['method'] as String)),
            ]),
            _Section(title: 'Cash movement by transaction date', children: [
              Text(report.meta['cash_basis'] as String),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Collections'),
                  subtitle: Text(_money(report.cashFlow['collected'])),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _details(context, ref, kind: 'event_payments')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Refunds issued'),
                  subtitle: Text(_money(report.cashFlow['refunds'])),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _details(context, ref, kind: 'event_refunds')),
              _AmountLine('Net collections', report.cashFlow['net']),
              if (report.cashFlow['unassigned_cash_payments'] != 0 ||
                  report.cashFlow['unassigned_cash_refunds'] != 0)
                Text(
                    'Needs reconciliation: ${report.cashFlow['unassigned_cash_payments']} cash payment(s) and ${report.cashFlow['unassigned_cash_refunds']} cash refund(s) without a shift.'),
            ]),
            _Section(title: 'Cash drawer reconciliation', children: [
              const Text(
                  'Whole shifts overlapping these dates, for all cashiers and categories in the selected branches. Opening + cash receipts − cash refunds + cash in − cash out = expected cash.'),
              if (report.shifts['total'] == 0)
                const Text('No shifts overlap these dates.'),
              if ((report.shifts['total'] as int) > 50)
                Text(
                    'Showing the latest 50 of ${report.shifts['total']} shifts. Choose a shorter date range to review earlier shifts.'),
              for (final shift in SalesReport.maps(report.shifts['rows']))
                ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                        '${shift['cashier_name']} · Shift ${shift['id']} · ${shift['status']}'),
                    subtitle: Text(
                        'Expected ${_money(shift['expected'])}${shift['difference'] == null ? '' : ' · Difference ${_money(shift['difference'])}'}'),
                    children: [
                      Text(branches.firstWhere(
                              (b) => b['id'] == shift['branch_id'])['name']
                          as String),
                      for (final entry in const {
                        'opening': 'Opening cash',
                        'cash_sales': 'Cash receipts',
                        'cash_refunds': 'Cash refunds',
                        'cash_in': 'Cash in',
                        'cash_out': 'Cash out',
                        'expected': 'Expected cash',
                        'recorded_expected': 'Recorded at close',
                        'counted': 'Counted cash',
                        'difference': 'Difference'
                      }.entries)
                        if (shift[entry.key] != null)
                          _AmountLine(entry.value, shift[entry.key]),
                    ]),
            ]),
            _SalesExports(report: report),
            const SizedBox(height: 12),
            Text(
                'Updated ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(report.meta['generated_at'] as String).toLocal())} · this device’s time'),
            const Text(
                'Pending offline orders appear after successful sync. Pull down to refresh.'),
          ],
        ));
  }

  void _details(BuildContext context, WidgetRef ref,
      {required String kind, String? metric, String? method}) {
    final query = ref
        .read(salesReportsControllerProvider.notifier)
        .query
        .periodSelection('custom', from: report.from, to: report.to);
    final branch = ref.read(currentBranchProvider)?.id;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SalesReportDetailsScreen(
            query: query,
            branchId: branch,
            kind: kind,
            metric: metric,
            method: method)));
  }
}

class _ReportFilter extends StatelessWidget {
  const _ReportFilter(
      {required this.label,
      required this.value,
      required this.options,
      required this.onChanged});
  final String label;
  final int? value;
  final List<Map<String, dynamic>> options;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('All')),
        for (final option in options)
          DropdownMenuItem(
              value: option['id'] as int,
              child: Text(option['name'] as String,
                  overflow: TextOverflow.ellipsis))
      ],
      onChanged: onChanged);
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label,
      required this.value,
      required this.comparison,
      required this.isMoney,
      required this.onTap});
  final String label;
  final String value;
  final Map<String, dynamic> comparison;
  final bool isMoney;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final delta = isMoney
        ? ReportAmount.parse(comparison['delta']).money
        : '${comparison['delta']}';
    final previous = isMoney
        ? ReportAmount.parse(comparison['previous']).money
        : '${comparison['previous']}';
    final change = comparison['percent'] == null
        ? (comparison['status'] == 'new'
            ? 'New · previous period was zero'
            : 'No change · both periods zero')
        : '${comparison['percent']}% vs previous period';
    return Card(
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      const SizedBox(height: 6),
                      Text(value,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(change),
                      Text('Previous: $previous'),
                      Text('Change: $delta'),
                      const SizedBox(height: 4),
                      const Text('View source orders',
                          style: TextStyle(fontSize: 12)),
                    ]))));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ])));
}

class _AmountLine extends StatelessWidget {
  const _AmountLine(this.label, this.value);
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [Text(label), Text(_money(value))]));
}

class _SalesExports extends StatefulWidget {
  const _SalesExports({required this.report});
  final SalesReport report;
  @override
  State<_SalesExports> createState() => _SalesExportsState();
}

class _SalesExportsState extends State<_SalesExports> {
  bool busy = false;
  Future<void> export(ReportExportFormat format) async {
    if (busy) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final report = widget.report;
      final file = await ReportExporter.buildRows(salesReportRows(report),
          'top-coffee-sales-${report.from}-${report.to}', format);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [
        XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)
      ], fileNameOverrides: [
        file.name
      ], subject: 'Top Coffee POS sales report', sharePositionOrigin: origin));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not export this report. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final format in ReportExportFormat.values)
          OutlinedButton.icon(
              onPressed: busy ? null : () => export(format),
              icon: const Icon(Icons.download_outlined),
              label: Text(format == ReportExportFormat.xlsx
                  ? 'Excel'
                  : format.name.toUpperCase())),
        if (busy) const CircularProgressIndicator(),
      ]);
}

List<List<Object>> salesReportRows(SalesReport report) => [
      ['Top Coffee POS · Sales report'],
      [
        'Branches and timezones',
        SalesReport.maps(report.meta['branches'])
            .map((b) => '${b['name']} (${b['timezone']})')
            .join('; ')
      ],
      ['From', report.from],
      ['To', report.to],
      [
        'Previous period',
        '${report.meta['previous_from']} – ${report.meta['previous_to']}'
      ],
      ['Cashier', _selectedFilterName(report, 'cashier')],
      ['Category', _selectedFilterName(report, 'category')],
      ['Sales basis', report.meta['sales_basis'] as String],
      ['Category basis', report.meta['category_basis'] as String],
      ['Metric (USD)', 'Value', 'Change vs previous period'],
      for (final metric in reportMetricLabels.entries)
        [
          metric.value,
          metric.key == 'total_orders'
              ? report.summary[metric.key] as int
              : report.amount(metric.key),
          report.comparisons[metric.key]['percent'] == null
              ? report.comparisons[metric.key]['status'] as String
              : '${report.comparisons[metric.key]['percent']}%'
        ],
      ['Excluded completed orders', report.summary['excluded_orders'] as int],
      [
        'Payment reconciliation difference',
        report.amount('payment_difference')
      ],
      [],
      ['Period', 'Order totals (USD)'],
      for (final row in report.timeline)
        [
          '${row['date_from']} – ${row['date_to']}',
          ReportAmount.parse(row['total'])
        ],
      [],
      ['Hourly sales', 'Order totals (USD)'],
      for (final row in report.hourlySales)
        [row['hour'] as String, ReportAmount.parse(row['total'])],
      [],
      ['Top products before discounts', 'Quantity', 'Sales (USD)'],
      for (final row in report.topProducts)
        [
          row['product_name'] as String,
          row['quantity'] as int,
          ReportAmount.parse(row['total'])
        ],
      [],
      ['Order type', 'Count', 'Order totals (USD)'],
      for (final row in report.orderTypes)
        [
          row['type'] as String,
          row['count'] as int,
          ReportAmount.parse(row['total'])
        ],
      [],
      ['Payment method', 'Collected (USD)', 'Refunds (USD)', 'Net (USD)'],
      for (final row in report.paymentMethods)
        [
          row['method'] as String,
          ReportAmount.parse(row['collected']),
          ReportAmount.parse(row['refunds']),
          ReportAmount.parse(row['net'])
        ],
      [],
      [
        'Transaction-date collections',
        ReportAmount.parse(report.cashFlow['collected'])
      ],
      [
        'Transaction-date refunds',
        ReportAmount.parse(report.cashFlow['refunds'])
      ],
      ['Transaction-date net', ReportAmount.parse(report.cashFlow['net'])],
      ['Cash basis', report.meta['cash_basis'] as String],
      [
        'Shift results shown',
        SalesReport.maps(report.shifts['rows']).length,
        'Total overlapping shifts: ${report.shifts['total']}'
      ],
      for (final row in SalesReport.maps(report.shifts['rows'])) ...[
        [
          'Shift ${row['id']} · ${row['cashier_name']}',
          'Branch ${row['branch_id']}',
          row['status'] as String
        ],
        ['Opening', ReportAmount.parse(row['opening'])],
        ['Cash receipts', ReportAmount.parse(row['cash_sales'])],
        ['Cash refunds', ReportAmount.parse(row['cash_refunds'])],
        ['Cash in', ReportAmount.parse(row['cash_in'])],
        ['Cash out', ReportAmount.parse(row['cash_out'])],
        ['Expected', ReportAmount.parse(row['expected'])],
        [
          'Counted',
          row['counted'] == null
              ? 'Open / not counted'
              : ReportAmount.parse(row['counted'])
        ],
        [
          'Difference',
          row['difference'] == null
              ? 'Open / not counted'
              : ReportAmount.parse(row['difference'])
        ],
      ],
    ];

String _date(String date) =>
    DateFormat('dd MMM yyyy').format(DateTime.parse(date));
String _money(Object? value) => ReportAmount.parse(value).money;
String _method(Object? value) =>
    value == 'qr' ? 'QR' : '${value ?? ''}'.toUpperCase();

String _selectedFilterName(SalesReport report, String field) {
  final id = report.meta['${field}_id'];
  if (id == null) return 'All';
  final rows = SalesReport.maps(
      report.meta[field == 'cashier' ? 'cashiers' : 'categories']);
  return rows.firstWhere((row) => row['id'] == id)['name'] as String;
}
