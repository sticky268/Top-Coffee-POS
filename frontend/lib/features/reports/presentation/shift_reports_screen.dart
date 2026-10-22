import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../application/sales_reports_controller.dart';
import '../domain/sales_report.dart';
import 'report_overview_widgets.dart';

class ShiftReportsScreen extends ConsumerWidget {
  const ShiftReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesReportsControllerProvider);
    final controller = ref.read(salesReportsControllerProvider.notifier);
    return Scaffold(
        appBar: const PageAppBar(title: Text('Shift reports')),
        body: PageContent(
            maxWidth: 1000,
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: FilledButton(
                      onPressed: controller.refresh,
                      child: const Text('Retry shifts'))),
              data: (report) {
                final rows = SalesReport.maps(report.shifts['rows']);
                final branches = SalesReport.maps(report.meta['branches']);
                return RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: ListView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const ReportIntro(
                              title: 'Every shift, accounted for',
                              subtitle:
                                  'Review cash expectations, counts and differences.',
                              icon: Icons.fact_check_outlined),
                          ReportPeriodChips(
                              selected: controller.query.period,
                              onSelected: (p) => controller
                                  .select(controller.query.periodSelection(p))),
                          Text('${report.from} – ${report.to}',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text(
                              'Whole shifts overlapping these dates, across all cashiers and categories in the selected branches.'),
                          const SizedBox(height: 16),
                          if ((report.shifts['total'] as int) > 50)
                            Text(
                                'Showing the latest 50 of ${report.shifts['total']} shifts. Select a shorter period for earlier shifts.'),
                          if (rows.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 48),
                                child: Column(children: [
                                  Icon(Icons.coffee_outlined,
                                      size: 48,
                                      color: AppColors.semantic(
                                          context, AppColors.ready)),
                                  const SizedBox(height: 16),
                                  Text('No shifts in this period',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Try another date range. Recorded shifts will appear here.',
                                      textAlign: TextAlign.center),
                                ])),
                          for (final shift in rows)
                            Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ExpansionTile(
                                  key: PageStorageKey(
                                      'report-shift-${shift['id']}'),
                                  leading: Icon(
                                      shift['status'] == 'closed'
                                          ? Icons.task_alt_rounded
                                          : Icons.timelapse_rounded,
                                      color: AppColors.semantic(
                                          context, AppColors.ready)),
                                  title: Text(
                                      '${shift['cashier_name']} · Shift ${shift['id']}'),
                                  subtitle: Text(
                                      '${shift['status']} · Expected ${reportDisplayValue(ReportAmount.parse(shift['expected']).money)}\n${shift['difference'] == null ? 'Cash count pending' : 'Difference ${reportDisplayValue(ReportAmount.parse(shift['difference']).money)}'}'),
                                  childrenPadding: const EdgeInsets.all(16),
                                  children: [
                                    Text(branches
                                        .where((b) =>
                                            b['id'] == shift['branch_id'])
                                        .map((b) => '${b['name']}')
                                        .join(', ')),
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
                                        ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(entry.value),
                                            subtitle: Text(reportDisplayValue(
                                                ReportAmount.parse(
                                                        shift[entry.key])
                                                    .money))),
                                  ],
                                )),
                        ]));
              },
            )));
  }
}
