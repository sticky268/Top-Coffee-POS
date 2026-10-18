import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../auth/presentation/manager_pin_prompt.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/receipt/customer_bill.dart';
import '../../pos/presentation/widgets/checkout_summary.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../core/widgets/receipt_action_buttons.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../pos/data/pos_repository.dart';
import '../application/orders_list_controller.dart';
import '../application/order_detail_controller.dart';
import '../application/order_detail_state.dart';
import '../domain/order_models.dart';
import 'widgets/order_status_helpers.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailControllerProvider(orderId));
    final authState = ref.watch(authControllerProvider);

    final canEditHeld = state is OrderDetailLoaded &&
        state.order.status == 'held' &&
        state.order.orderType == 'dine_in' &&
        authState is AuthAuthenticated &&
        authState.user.hasPermission('orders.create');

    final canAdjustCompleted = state is OrderDetailLoaded &&
        state.order.status == 'completed' &&
        state.order.supplementalTotal == 0 &&
        state.order.refundedTotal == 0 &&
        authState is AuthAuthenticated &&
        authState.user.hasPermission('orders.edit');

    final canCancel = state is OrderDetailLoaded &&
        state.order.status == 'held' &&
        state.order.orderType == 'dine_in' &&
        authState is AuthAuthenticated &&
        authState.user.hasPermission('orders.cancel');

    final appBarTitle = state is OrderDetailLoaded
        ? 'Order ${state.order.displayOrderReference}'
        : 'Order';

    return Scaffold(
      appBar: PageAppBar(
        title: Text(appBarTitle),
        actions: [
          if (state is OrderDetailLoaded && state.order.status == 'completed')
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Payment history and corrections',
              onPressed: () async {
                await context.push<void>('/orders/$orderId/financials');
                if (context.mounted) {
                  await ref
                      .read(orderDetailControllerProvider(orderId).notifier)
                      .refresh();
                }
              },
            ),
          if (canCancel)
            pos_ui.IconButton(
              tooltip: 'Cancel order',
              icon: const Icon(Icons.cancel_outlined),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Cancel Order?'),
                    content: const Text(
                      'This will cancel the held order and release its table. '
                      'The order will remain in history. This cannot be undone.',
                    ),
                    actions: [
                      pos_ui.SecondaryButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Keep Order'),
                      ),
                      pos_ui.DangerButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Cancel Order'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                try {
                  final pin = await requestManagerPin(
                    context,
                    ref,
                    action: 'Approve order cancellation',
                  );
                  if (pin == null || !context.mounted) return;
                  final repo = ref.read(posRepositoryProvider);
                  if (pin.isEmpty) {
                    await repo.cancelHeldOrder(orderId: orderId);
                  } else {
                    await repo.cancelHeldOrder(
                      orderId: orderId,
                      managerPin: pin,
                      branchId: ref.read(currentBranchProvider)?.id,
                    );
                  }
                  await ref
                      .read(ordersListControllerProvider.notifier)
                      .refresh();
                  if (!context.mounted) return;
                  await ref
                      .read(orderDetailControllerProvider(orderId).notifier)
                      .refresh();
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error is ApiException
                            ? error.message
                            : 'Could not cancel order. Refresh its status before trying again.',
                      ),
                    ),
                  );
                }
              },
            ),
          if (canEditHeld)
            pos_ui.IconButton(
              tooltip: 'Edit open order',
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await context.push<bool>('/pos/open-order/$orderId');
                if (context.mounted) {
                  await ref
                      .read(orderDetailControllerProvider(orderId).notifier)
                      .refresh();
                }
              },
            ),
        ],
      ),
      body: PageContent(
        maxWidth: 800,
        child: switch (state) {
          OrderDetailLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          OrderDetailError(:final message) => _DetailErrorView(
              message: message,
              onRetry: () => ref
                  .read(orderDetailControllerProvider(orderId).notifier)
                  .refresh(),
            ),
          OrderDetailLoaded(:final order) => _OrderDetailBody(
              order: order,
              onAdjustCompleted: canAdjustCompleted
                  ? () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Adjust completed order?'),
                          content: const Text(
                            'This changes a completed historical sale and updates inventory. '
                            'The final total must stay equal to the amount already paid. '
                            'Use the refund or additional payment workflow for payment changes.',
                          ),
                          actions: [
                            pos_ui.SecondaryButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            pos_ui.PrimaryButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('Adjust Order'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed != true || !context.mounted) return;
                      final changed = await context.push<bool>(
                        '/orders/$orderId/edit',
                      );
                      if (context.mounted && changed == true) {
                        await ref
                            .read(
                                orderDetailControllerProvider(orderId).notifier)
                            .refresh();
                      }
                    }
                  : null,
            ),
        },
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({required this.order, this.onAdjustCompleted});

  final OrderDetail order;
  final VoidCallback? onAdjustCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final dateLabel = order.createdAt != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(order.createdAt!)
        : 'Unknown date';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order ${order.displayOrderReference}',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  label: 'Status',
                  value: orderStatusLabel(order.status),
                ),
                _InfoRow(label: 'Type', value: orderTypeLabel(order.orderType)),
                if (order.table != null)
                  _InfoRow(label: 'Table', value: order.table!.name),
                // Defensive per this feature's requirement — a historical
                // order's branch/cashier could be missing; never crash,
                // always show a sensible fallback.
                _InfoRow(
                  label: 'Branch',
                  value: order.branch?.name ?? 'Unknown',
                ),
                _InfoRow(
                  label: 'Cashier',
                  value: order.cashier?.name ?? 'Unknown',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: order.items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No items recorded',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final item in order.items)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: CheckoutOrderLine(
                          title: item.productName,
                          variant: item.variantName,
                          quantity: item.quantity,
                          unitPrice: currency.format(item.unitPrice),
                          lineTotal: currency.format(item.lineTotal),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryRow(
                  label: 'Subtotal',
                  value: currency.format(order.subtotal),
                ),
                if (order.discountTotal > 0)
                  _SummaryRow(
                    label: 'Discount',
                    value: '- ${currency.format(order.discountTotal)}',
                  ),
                const Divider(height: 16),
                _SummaryRow(
                  label: 'Total',
                  value: currency.format(order.total),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ),
        if (order.payment != null || order.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final payment in (order.payments.isNotEmpty
                      ? order.payments
                      : [order.payment!])) ...[
                    _InfoRow(
                      label: 'Method',
                      value: paymentMethodLabel(payment.method),
                    ),
                    _InfoRow(label: 'Status', value: payment.status),
                    _InfoRow(
                      label: 'Amount',
                      value: currency.format(payment.amount),
                    ),
                    if (payment.tendered != null)
                      _InfoRow(
                        label: 'Tendered',
                        value: currency.format(payment.tendered),
                      ),
                    if (payment.changeDue != null)
                      _InfoRow(
                        label: 'Change Due',
                        value: currency.format(payment.changeDue),
                      ),
                    if (order.payments.length > 1 &&
                        payment != order.payments.last)
                      const Divider(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (onAdjustCompleted != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Completed sale',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Adjustments are restricted and recorded in the audit log.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  pos_ui.OutlinedButton.icon(
                    onPressed: onAdjustCompleted,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Adjust Order'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (order.status == 'held') ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BillActionButtons(
                bill: CustomerBill.fromOrderDetail(order),
                showHeading: true,
              ),
            ),
          ),
        ],
        if (canIssueReceiptForOrderStatus(order.status)) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ReceiptActionButtons(orderId: order.id, showHeading: true),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DetailValue(label: label, value: value);
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: CheckoutAmountRow(
        label: label,
        value: value,
        emphasized: emphasize,
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Could not load this order',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
