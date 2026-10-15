import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/branch/current_branch_provider.dart';
import '../../../../core/offline/order_sync.dart';
import '../../../../core/offline/order_sync_summary.dart';
import '../../../../core/printer/print_queue.dart';
import '../../../../core/printer/print_queue_providers.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';

/// Local exceptions remain visible even when the server dashboard is offline.
/// Counts are for this cashier's selected branch on this device, never a
/// business-wide claim about other devices' queues.
class DashboardAttentionPanel extends ConsumerWidget {
  const DashboardAttentionPanel({super.key, this.lowStockCount,
    this.cashDiscrepancyCount, this.cashDiscrepancyShiftId});
  final int? lowStockCount;
  final int? cashDiscrepancyCount;
  final int? cashDiscrepancyShiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final branch = ref.watch(currentBranchProvider);
    if (auth is! AuthAuthenticated || branch == null ||
        (!auth.user.hasPermission('branches.view-all') &&
            !auth.user.branches.any((item) => item.id == branch.id))) {
      return const SizedBox.shrink();
    }
    final user = auth.user;
    final cards = <Widget>[];
    if (user.hasPermission('orders.create') ||
        user.hasPermission('orders.view')) {
      final orders = ref.watch(pendingOrdersProvider);
      cards.addAll(orders.when(
        skipLoadingOnReload: false,
        data: (items) {
          final summary = OrderSyncSummary.fromOrders(items);
          if (!summary.needsAttention) return <Widget>[];
          return <Widget>[
            _AttentionRow(
              icon: Icons.cloud_upload_outlined,
              title: summary.needsReview > 0
                  ? '${summary.needsReview} ${summary.needsReview == 1 ? 'saved order needs' : 'saved orders need'} review'
                  : '${summary.waiting} ${summary.waiting == 1 ? 'saved order awaits' : 'saved orders await'} confirmation',
              detail: '${summary.waiting} awaiting confirmation · '
                  '${summary.needsReview} need review. '
                  'Saved on this device; check before taking payment again.',
              onTap: () => context.push('/pending-orders'),
            ),
          ];
        },
        loading: () => <Widget>[
          const _AttentionRow(
            icon: Icons.cloud_upload_outlined,
            title: 'Checking saved orders…',
            detail: 'On this device',
          ),
        ],
        error: (error, stack) => <Widget>[
          _AttentionRow(
            icon: Icons.cloud_off_outlined,
            title: 'Saved order status unavailable',
            detail: 'Open saved orders to check. No confirmation is assumed.',
            onTap: () => context.push('/pending-orders'),
          ),
        ],
      ));
      final jobs = ref.watch(printJobsProvider);
      cards.addAll(jobs.when(
        skipLoadingOnReload: false,
        data: (items) {
          final failed = items.where((job) =>
              job.status == PrintStatus.failed ||
              job.status == PrintStatus.uncertain).length;
          final waiting = items.where((job) =>
              job.status == PrintStatus.waiting ||
              job.status == PrintStatus.sending).length;
          if (failed + waiting == 0) return <Widget>[];
          return <Widget>[
            _AttentionRow(
              icon: Icons.print_outlined,
              title: failed > 0
                  ? '$failed ${failed == 1 ? 'receipt needs' : 'receipts need'} attention'
                  : '$waiting ${waiting == 1 ? 'receipt' : 'receipts'} waiting to print',
              detail: '$waiting waiting or sending · $failed need review. '
                  'Check the paper before retrying uncertain output.',
              onTap: () => context.push('/print-queue'),
            ),
          ];
        },
        loading: () => <Widget>[
          const _AttentionRow(
            icon: Icons.print_outlined,
            title: 'Checking receipts…',
            detail: 'On this device',
          ),
        ],
        error: (error, stack) => <Widget>[
          _AttentionRow(
            icon: Icons.print_disabled_outlined,
            title: 'Receipt status unavailable',
            detail: 'Open the print queue to check existing attempts.',
            onTap: () => context.push('/print-queue'),
          ),
        ],
      ));
    }
    if (user.hasPermission('reports.view') &&
        cashDiscrepancyCount != null && cashDiscrepancyCount! > 0) {
      cards.add(_AttentionRow(
        icon: Icons.account_balance_wallet_outlined,
        title: '$cashDiscrepancyCount ${cashDiscrepancyCount == 1 ? 'shift has' : 'shifts have'} an unreviewed cash difference',
        detail: 'Server-recorded cash shortages or overages in ${branch.name}. Review each shift before confirming.',
        onTap: () => context.push(cashDiscrepancyShiftId == null
            ? '/operations?section=Shifts&review=differences'
            : '/operations?section=Shifts&shift_id=$cashDiscrepancyShiftId&review=differences'),
      ));
    }
    if (user.hasPermission('inventory.view') &&
        lowStockCount != null && lowStockCount! > 0) {
      cards.add(_AttentionRow(
        icon: Icons.inventory_2_outlined,
        title: '$lowStockCount ${lowStockCount == 1 ? 'ingredient needs' : 'ingredients need'} restocking',
        detail: 'At or below the reorder threshold in ${branch.name}.',
        onTap: () => context.push('/inventory?filter=low-stock'),
      ));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Needs attention', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${branch.name} · saved orders and receipts are from this account on this device',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...cards,
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(detail),
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
