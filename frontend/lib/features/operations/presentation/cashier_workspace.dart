import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/order_sync.dart';
import '../../../core/theme/home_layout_preference.dart';
import '../../dashboard/presentation/widgets/home_dashboard_layouts.dart';
import '../../dashboard/presentation/widgets/quick_actions_grid.dart';
import '../../../core/offline/order_sync_summary.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../dashboard/presentation/widgets/dashboard_header.dart';
import '../data/operations_repository.dart';

class CashierWorkspace extends ConsumerWidget {
  const CashierWorkspace({super.key, required this.user});
  final AuthenticatedUser user;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final shifts = ref.watch(shiftsProvider);
    final pending = ref.watch(pendingOrdersProvider);
    final open = shifts.asData?.value
        .where((s) => s['user_id'] == user.id && s['status'] == 'open')
        .toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DashboardHeader(
              user: user,
              showBrand: MediaQuery.sizeOf(context).width >= 900 &&
                  layout != HomeLayout.coffeeCounter,
              onLogout: () =>
                  ref.read(authControllerProvider.notifier).logout(),
            ),
            const SizedBox(height: 24),
            Text(
              'Cashier workspace',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(
                  open == null
                      ? 'Check your shift'
                      : open.isEmpty
                          ? 'Open your shift'
                          : 'Shift #${open.first['id']} is open',
                ),
                subtitle: const Text(
                  'Opening cash, cash movements and end-of-shift count',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/operations'),
              ),
            ),
            const SizedBox(height: 16),
            if (layout != HomeLayout.classic)
              HomeTaskPanel(
                  title: 'Start here',
                  colorful: layout == HomeLayout.coffeeCounter,
                  featureFirst: layout == HomeLayout.coffeeCounter,
                  actions: [
                    if (user.hasPermission('orders.create')) ...[
                      QuickAction(
                          label: 'New takeaway order',
                          icon: Icons.shopping_bag_outlined,
                          onTap: () => context.go('/pos')),
                      QuickAction(
                          label: 'Dine-in / tables',
                          icon: Icons.table_restaurant_outlined,
                          onTap: () => context.go('/pos/select-table')),
                    ],
                    if (user.hasPermission('orders.view'))
                      QuickAction(
                          label: 'Orders',
                          icon: Icons.receipt_long_outlined,
                          onTap: () => context.go('/orders')),
                  ])
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (user.hasPermission('orders.create')) ...[
                    FilledButton.icon(
                      onPressed: () => context.go('/pos'),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('New takeaway order'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/pos/select-table'),
                      icon: const Icon(Icons.table_restaurant_outlined),
                      label: const Text('Dine-in / tables'),
                    ),
                  ],
                  if (user.hasPermission('orders.view'))
                    OutlinedButton.icon(
                      onPressed: () => context.go('/orders'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Orders'),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Saved orders'),
                subtitle: Text(
                  pending.when(
                    data: (orders) =>
                        OrderSyncSummary.fromOrders(orders).description,
                    loading: () => 'Checking saved orders…',
                    error: (_, __) => 'Could not check saved orders',
                  ),
                ),
                onTap: () => context.go('/pending-orders'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
