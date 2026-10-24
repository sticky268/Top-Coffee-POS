import 'package:flutter/material.dart';
import '../../../core/theme/coffee_studio_theme.dart';
import '../../../core/widgets/studio_layout.dart';
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
import 'trends_screen.dart';
import 'shift_reports_screen.dart';
import 'report_overview_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../audit_log/presentation/audit_log_screen.dart';
import '../../customers/presentation/customers_screen.dart';
import '../../expenses/presentation/expenses_screen.dart';

/// The menu opens without a network request; each report owns its loading state.
class ReportsHomeScreen extends ConsumerWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    void open(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    if (CoffeeStudioTheme.active(context)) {
      Widget group(String title, List<StudioAction> actions) => Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StudioActionBoard(actions: actions),
          ]));
      return Scaffold(
        appBar: const PageAppBar(title: Text('Reports')),
        body: PageContent(
            maxWidth: 1300,
            child: ListView(padding: const EdgeInsets.all(28), children: [
              Text('Reports',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(branch?.name ?? 'Choose a branch on the dashboard'),
              const SizedBox(height: 28),
              group('Sales & revenue', [
                StudioAction(
                    'Sale Reports',
                    'Daily and monthly sales',
                    Icons.calendar_month_outlined,
                    () => open(const SalesHistoryScreen())),
                StudioAction(
                    'Sales summary',
                    'Totals, payments and reconciliation',
                    Icons.bar_chart_rounded,
                    () => open(const ReportsScreen())),
                StudioAction(
                    'Sales trends',
                    'Daily and monthly momentum',
                    Icons.stacked_line_chart_rounded,
                    () => open(const ReportWorkspaceScreen(
                        kind: ReportWorkspace.trends))),
                StudioAction(
                    'Profit & product performance',
                    'Recipe costs, margins and top items',
                    Icons.pie_chart_outline,
                    () => open(const ReportWorkspaceScreen(
                        kind: ReportWorkspace.profit))),
                StudioAction(
                    'Branch comparison',
                    'Compare accessible branches',
                    Icons.store_outlined,
                    () => open(const ReportWorkspaceScreen(
                        kind: ReportWorkspace.branches))),
              ]),
              group('Operations', [
                StudioAction(
                    'Shift reports',
                    'Cash counts and differences',
                    Icons.fact_check_outlined,
                    () => open(const ShiftReportsScreen())),
                StudioAction(
                    'Time & cashier performance',
                    'Busy hours and staff activity',
                    Icons.schedule_outlined,
                    () => open(const ReportWorkspaceScreen(
                        kind: ReportWorkspace.activity))),
                StudioAction(
                    'Inventory report',
                    'Stock, waste and usage',
                    Icons.inventory_2_outlined,
                    () => open(const ReportWorkspaceScreen(
                        kind: ReportWorkspace.inventory))),
                if (user?.hasPermission('expenses.manage') ?? false)
                  StudioAction(
                      'Expenses',
                      'Recorded business expenses',
                      Icons.receipt_outlined,
                      () => open(const ExpensesScreen())),
                if (user?.hasPermission('orders.view') ?? false)
                  StudioAction(
                      'Transactions',
                      'Order and payment details',
                      Icons.swap_horiz,
                      () => open(const OrdersScreen(title: 'Transactions'))),
                if (user?.hasPermission('audit.view') ?? false)
                  StudioAction('Audit history', 'Who changed what and when',
                      Icons.history, () => open(const AuditLogScreen())),
              ]),
              if ((user?.hasPermission('customers.view') ?? false) ||
                  (user?.hasPermission('customers.manage') ?? false))
                group('Customers', [
                  StudioAction(
                      'Customers & points',
                      'Activity and loyalty history',
                      Icons.people_outline,
                      () => open(const CustomersScreen())),
                ]),
              const Text(
                  'Reports include sales after they have synced successfully.'),
            ])),
      );
    }
    return Scaffold(
      appBar: const PageAppBar(title: Text('Reports')),
      body: PageContent(
        maxWidth: 1000,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ReportIntro(
                title: 'The coffee shop, in focus',
                subtitle:
                    'Sales, people and stock — one clear view.\n${branch?.name ?? 'All accessible branches'}'),
            _heading(context, 'Sales & revenue'),
            _ReportLink(
              title: 'Sale Reports',
              subtitle: 'Daily and monthly sales, item counts and top periods',
              icon: Icons.calendar_month_outlined,
              color: AppColors.info,
              onTap: () => open(const SalesHistoryScreen()),
            ),
            _ReportLink(
              title: 'Sales summary',
              subtitle: 'Totals, payments, refunds and cash reconciliation',
              icon: Icons.bar_chart_rounded,
              color: AppColors.ready,
              onTap: () => open(const ReportsScreen()),
            ),
            _ReportLink(
                title: 'Sales trends',
                subtitle: 'Daily momentum and six months of sales history',
                icon: Icons.stacked_line_chart_rounded,
                color: AppColors.warning,
                onTap: () => open(
                    const ReportWorkspaceScreen(kind: ReportWorkspace.trends))),
            _ReportLink(
              title: 'Profit & product performance',
              subtitle: 'Recipe costs, margins and best-selling products',
              icon: Icons.pie_chart_outline,
              color: AppColors.plum,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.profit),
              ),
            ),
            if (user?.hasPermission('expenses.manage') ?? false)
              _ReportLink(
                  title: 'Expenses',
                  subtitle: 'Review recorded business expenses and categories',
                  icon: Icons.receipt_outlined,
                  color: AppColors.warning,
                  onTap: () => open(const ExpensesScreen())),
            _ReportLink(
              title: 'Branch comparison',
              subtitle: 'Compare revenue, margin and growth across branches',
              icon: Icons.store_outlined,
              color: AppColors.warning,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.branches),
              ),
            ),
            const SizedBox(height: 16),
            _heading(context, 'Operations & management'),
            _ReportLink(
                title: 'Shift reports',
                subtitle: 'Cash counts, expected balances and differences',
                icon: Icons.fact_check_outlined,
                color: AppColors.ready,
                onTap: () => open(const ShiftReportsScreen())),
            if (user?.hasPermission('orders.view') ?? false)
              _ReportLink(
                  title: 'Transactions',
                  subtitle: 'Search orders, payments and receipt details',
                  icon: Icons.swap_horiz_rounded,
                  color: AppColors.info,
                  onTap: () => open(const OrdersScreen(title: 'Transactions'))),
            if (user?.hasPermission('audit.view') ?? false)
              _ReportLink(
                  title: 'Audit history',
                  subtitle: 'Recorded changes, actions and who made them',
                  icon: Icons.history_rounded,
                  color: AppColors.warning,
                  onTap: () => open(const AuditLogScreen())),
            _ReportLink(
              title: 'Time & cashier performance',
              subtitle: 'Busy hours, cashier activity, discounts and voids',
              icon: Icons.schedule_outlined,
              color: AppColors.info,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.activity),
              ),
            ),
            _ReportLink(
              title: 'Inventory report',
              subtitle: 'Stock value, low stock, waste and recipe usage',
              icon: Icons.inventory_2_outlined,
              color: AppColors.warning,
              onTap: () => open(
                const ReportWorkspaceScreen(kind: ReportWorkspace.inventory),
              ),
            ),
            if ((user?.hasPermission('customers.view') ?? false) ||
                (user?.hasPermission('customers.manage') ?? false)) ...[
              const SizedBox(height: 16),
              _heading(context, 'Customers & loyalty'),
              _ReportLink(
                  title: 'Customers & points',
                  subtitle: 'Customer activity, balances and loyalty history',
                  icon: Icons.people_outline_rounded,
                  color: AppColors.plum,
                  onTap: () => open(const CustomersScreen())),
            ],
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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

enum ReportWorkspace { profit, branches, activity, inventory, trends }

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
                  onPressed:
                      ref.read(salesReportsControllerProvider.notifier).refresh,
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
        void preset(String period) {
          final controller = ref.read(salesReportsControllerProvider.notifier);
          controller.select(controller.query.periodSelection(period));
        }

        final selected =
            ref.read(salesReportsControllerProvider.notifier).query.period;
        return switch (kind) {
          ReportWorkspace.trends =>
            TrendsScreen(key: key, query: query, branchId: branch),
          ReportWorkspace.profit => ProfitReportScreen(
              key: key,
              query: query,
              branchId: branch,
              onChangeFilters: filters,
              onPeriodChanged: preset,
              selectedPeriod: selected,
            ),
          ReportWorkspace.branches => BranchComparisonScreen(
              key: key,
              query: query,
              onChangeFilters: filters,
              onPeriodChanged: preset,
              selectedPeriod: selected,
            ),
          ReportWorkspace.activity => ActivityReportScreen(
              key: key,
              query: query,
              branchId: branch,
              onChangeFilters: filters,
              onPeriodChanged: preset,
              selectedPeriod: selected,
            ),
          ReportWorkspace.inventory => InventoryReportScreen(
              key: key,
              query: query,
              branchId: branch,
              onChangeFilters: filters,
              onPeriodChanged: preset,
              selectedPeriod: selected,
            ),
        };
      },
    );
  }
}
