import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../core/theme/home_layout_preference.dart';
import 'widgets/home_dashboard_layouts.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../application/dashboard_controller.dart';
import '../application/dashboard_state.dart';
import '../domain/dashboard_models.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/dashboard_attention_panel.dart';
import '../../operations/presentation/cashier_workspace.dart';
import 'widgets/quick_actions_grid.dart';
import 'widgets/recent_orders_section.dart';
import 'widgets/sales_overview_chart.dart';
import 'widgets/stat_cards_grid.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user != null && !user.hasPermission('reports.view')) {
      return CashierWorkspace(user: user);
    }
    final dashboardState = ref.watch(dashboardControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final contentWidth = (width - 32).clamp(0.0, 1280.0);
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final statColumns = (contentWidth / (textScale > 1.4 ? 240 : 160))
                .floor()
                .clamp(1, 4);
            final actionColumns = (contentWidth / (textScale > 1.4 ? 210 : 150))
                .floor()
                .clamp(1, 4);

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(dashboardControllerProvider.notifier).refresh(),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1312),
                  child: SingleChildScrollView(
                    key: PageStorageKey('home-scroll-${layout.name}'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user != null)
                          DashboardHeader(
                            user: user,
                            showBrand:
                                MediaQuery.sizeOf(context).width >= 900 &&
                                    layout != HomeLayout.coffeeCounter,
                            onLogout: () => ref
                                .read(authControllerProvider.notifier)
                                .logout(),
                          ),
                        const SizedBox(height: 24),
                        DashboardAttentionPanel(
                          lowStockCount: dashboardState is DashboardLoaded
                              ? dashboardState.stats.lowStockItemCount
                              : null,
                          cashDiscrepancyCount:
                              dashboardState is DashboardLoaded
                                  ? dashboardState.stats.cashDiscrepancyCount
                                  : null,
                          cashDiscrepancyShiftId:
                              dashboardState is DashboardLoaded
                                  ? dashboardState.stats.cashDiscrepancyShiftId
                                  : null,
                        ),
                        _DashboardBody(
                          state: dashboardState,
                          statColumns: statColumns,
                          actionColumns: actionColumns,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.state,
    required this.statColumns,
    required this.actionColumns,
  });

  final DashboardState state;
  final int statColumns;
  final int actionColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      DashboardLoading() => const _DashboardLoading(),
      DashboardError(:final message) => _DashboardErrorView(
          message: message,
          onRetry: () =>
              ref.read(dashboardControllerProvider.notifier).refresh(),
        ),
      DashboardLoaded(
        :final stats,
        :final recentOrders,
        :final salesOverview,
      ) =>
        _DashboardContent(
          stats: stats,
          recentOrders: recentOrders,
          salesOverview: salesOverview,
          statColumns: statColumns,
          actionColumns: actionColumns,
        ),
    };
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 300,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _DashboardErrorView extends StatelessWidget {
  const _DashboardErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Could not load the dashboard',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            pos_ui.PrimaryButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.stats,
    required this.recentOrders,
    required this.salesOverview,
    required this.statColumns,
    required this.actionColumns,
  });

  final DashboardStats stats;
  final List<RecentOrder> recentOrders;
  final List<SalesDataPoint> salesOverview;
  final int statColumns;
  final int actionColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    bool allowed(String permission) => user?.hasPermission(permission) ?? false;

    final actions = [
      if (allowed('orders.create') ||
          allowed('orders.refund') ||
          allowed('reports.view'))
        QuickAction(
          label: 'Daily Operations',
          icon: Icons.account_balance_wallet_outlined,
          onTap: () => context.push('/operations'),
        ),
      if (allowed('orders.create'))
        QuickAction(
          label: 'New Order',
          icon: Icons.add_shopping_cart,
          onTap: () => context.push('/pos'),
        ),
      if (allowed('orders.view'))
        QuickAction(
          label: 'Orders',
          icon: Icons.receipt_long_outlined,
          onTap: () => context.push('/orders'),
        ),
      if (allowed('customers.view'))
        QuickAction(
          label: 'Customers',
          icon: Icons.people_outline,
          onTap: () => context.push('/customers'),
        ),
      if (allowed('products.manage'))
        QuickAction(
          label: 'Manage Menu',
          icon: Icons.local_cafe_outlined,
          onTap: () => context.push('/manage-menu'),
        ),
      if (allowed('inventory.view'))
        QuickAction(
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          onTap: () => context.push('/inventory'),
        ),
      if (allowed('reports.view'))
        QuickAction(
          label: 'Reports',
          icon: Icons.bar_chart_outlined,
          onTap: () => context.push('/reports'),
        ),
      if (allowed('orders.create'))
        QuickAction(
          label: 'Receipt Settings',
          icon: Icons.receipt_long_outlined,
          onTap: () => context.push('/settings/receipt'),
        ),
    ];

    final layout = ref.watch(homeLayoutProvider);
    if (layout != HomeLayout.classic) {
      return HomeDashboardLayouts(
        layout: layout,
        stats: stats,
        actions: [
          ...actions,
          if (layout == HomeLayout.coffeeCounter && user != null)
            QuickAction(
                label: 'Settings',
                icon: Icons.settings_outlined,
                onTap: () => context.push('/settings')),
        ],
        recentOrders: recentOrders,
        salesOverview: salesOverview,
      );
    }
    return Column(
      key: const ValueKey('dashboard-classic'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatCardsGrid(stats: stats, crossAxisCount: statColumns),
        const SizedBox(height: 24),
        Text('Quick Actions', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        QuickActionsGrid(actions: actions, crossAxisCount: actionColumns),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final chart =
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Sales Overview — Last 7 Days',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SalesOverviewChart(data: salesOverview))),
          ]);
          final orders =
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Recent Orders', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            RecentOrdersSection(orders: recentOrders),
          ]);
          if (constraints.maxWidth >= 850 && scale <= 1.3) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: chart),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: orders),
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [chart, const SizedBox(height: 24), orders]);
        }),
      ],
    );
  }
}
