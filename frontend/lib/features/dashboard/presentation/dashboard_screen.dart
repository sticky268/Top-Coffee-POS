import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../application/dashboard_controller.dart';
import '../application/dashboard_state.dart';
import '../domain/dashboard_models.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/quick_actions_grid.dart';
import 'widgets/recent_orders_section.dart';
import 'widgets/sales_overview_chart.dart';
import 'widgets/stat_cards_grid.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(dashboardControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Phone: 2 stat columns / 3 action columns.
            // Tablet & desktop: 4 stat columns / 5 action columns (fits all
            // 5 quick actions in one row).
            final isCompact = width < 600;
            final statColumns = isCompact ? 2 : 4;
            final actionColumns = isCompact ? 3 : 5;

            return RefreshIndicator(
              onRefresh: () => ref.read(dashboardControllerProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user != null)
                      DashboardHeader(
                        user: user,
                        onLogout: () => ref.read(authControllerProvider.notifier).logout(),
                      ),
                    const SizedBox(height: 24),
                    _DashboardBody(
                      state: dashboardState,
                      statColumns: statColumns,
                      actionColumns: actionColumns,
                    ),
                  ],
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
          onRetry: () => ref.read(dashboardControllerProvider.notifier).refresh(),
        ),
      DashboardLoaded(:final stats, :final recentOrders, :final salesOverview) => _DashboardContent(
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
            const SizedBox(height: 12),
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
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
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

class _DashboardContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final actions = [
      QuickAction(
        label: 'New Order',
        icon: Icons.add_shopping_cart,
        onTap: () => context.push('/pos'),
      ),
      QuickAction(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        onTap: () => context.push('/orders'),
      ),
      QuickAction(
        label: 'Products',
        icon: Icons.local_cafe_outlined,
        onTap: () => context.push('/products'),
      ),
      QuickAction(
        label: 'Inventory',
        icon: Icons.inventory_2_outlined,
        onTap: () => context.push('/inventory'),
      ),
      QuickAction(
        label: 'Reports',
        icon: Icons.bar_chart_outlined,
        onTap: () => context.push('/reports'),
      ),
      QuickAction(
        label: 'Printer Test',
        icon: Icons.print_outlined,
        onTap: () => context.push('/printer-test'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatCardsGrid(stats: stats, crossAxisCount: statColumns),
        const SizedBox(height: 24),
        Text('Quick Actions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        QuickActionsGrid(actions: actions, crossAxisCount: actionColumns),
        const SizedBox(height: 24),
        Text('Sales Overview — Last 7 Days', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SalesOverviewChart(data: salesOverview),
          ),
        ),
        const SizedBox(height: 24),
        Text('Recent Orders', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        RecentOrdersSection(orders: recentOrders),
      ],
    );
  }
}
