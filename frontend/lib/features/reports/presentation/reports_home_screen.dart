import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../application/sales_reports_controller.dart';
import 'activity_report_screen.dart';
import 'branch_comparison_screen.dart';
import 'inventory_report_screen.dart';
import 'profit_report_screen.dart';
import 'reports_screen.dart';
import 'sales_history_screen.dart';

/// The menu opens without a network request; each report owns its loading state.
class ReportsHomeScreen extends ConsumerWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider);
    void open(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    return Scaffold(
      appBar: const PageAppBar(title: Text('Reports')),
      body: PageContent(
        maxWidth: 1000,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.insights_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reports & analytics',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Understand your sales, margins and daily operations.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    branch?.name ?? 'All accessible branches',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _heading(context, 'Sales & revenue'),
            _ReportLink(
              title: 'Sales summary',
              subtitle: 'Totals, payments, refunds and cash reconciliation',
              icon: Icons.bar_chart_rounded,
              color: Colors.teal,
              onTap: () => open(const ReportsScreen()),
            ),
            _ReportLink(
              title: 'Sales history',
              subtitle: 'Browse daily sales and every month of the year',
              icon: Icons.calendar_month_outlined,
              color: Colors.blue,
              onTap: () => open(const SalesHistoryScreen()),
            ),
            _ReportLink(
              title: 'Profit & product performance',
              subtitle: 'Recipe costs, margins and best-selling products',
              icon: Icons.pie_chart_outline,
              color: Colors.deepPurple,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.profit),
              ),
            ),
            _ReportLink(
              title: 'Branch comparison',
              subtitle: 'Compare revenue, margin and growth across branches',
              icon: Icons.store_outlined,
              color: Colors.orange,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.branches),
              ),
            ),
            const SizedBox(height: 16),
            _heading(context, 'Operations & management'),
            _ReportLink(
              title: 'Time & cashier performance',
              subtitle: 'Busy hours, cashier activity, discounts and voids',
              icon: Icons.schedule_outlined,
              color: Colors.indigo,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.activity),
              ),
            ),
            _ReportLink(
              title: 'Inventory report',
              subtitle: 'Stock value, low stock, waste and recipe usage',
              icon: Icons.inventory_2_outlined,
              color: Colors.brown,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.inventory),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Reports include sales after they have synced successfully.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _ReportLink extends StatelessWidget {
  const _ReportLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Color.lerp(color, Colors.white, .4)
                    : color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 22),
          ],
        ),
      ),
    ),
  );
}

enum ReportWorkspace { profit, branches, activity, inventory }

/// Shared server-resolved dates and filters feed every analytical report.
class ReportWorkspaceScreen extends ConsumerWidget {
  const ReportWorkspaceScreen({super.key, required this.kind});
  final ReportWorkspace kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesReportsControllerProvider);
    final branch = ref.watch(currentBranchProvider)?.id;
    void filters() {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
    }

    return state.when(
      loading: () => const Scaffold(
        appBar: PageAppBar(title: Text('Loading report')),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: const PageAppBar(title: Text('Report')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                FilledButton(
                  onPressed: ref
                      .read(salesReportsControllerProvider.notifier)
                      .refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (report) {
        final query = ref
            .read(salesReportsControllerProvider.notifier)
            .query
            .forProfit(report);
        final key = ValueKey('$kind/$branch/${query.parameters(branch)}');
        return switch (kind) {
          ReportWorkspace.profit => ProfitReportScreen(
            key: key,
            query: query,
            branchId: branch,
            onChangeFilters: filters,
          ),
          ReportWorkspace.branches => BranchComparisonScreen(
            key: key,
            query: query,
            onChangeFilters: filters,
          ),
          ReportWorkspace.activity => ActivityReportScreen(
            key: key,
            query: query,
            branchId: branch,
            onChangeFilters: filters,
          ),
          ReportWorkspace.inventory => InventoryReportScreen(
            key: key,
            query: query,
            branchId: branch,
            onChangeFilters: filters,
          ),
        };
      },
    );
  }
}
