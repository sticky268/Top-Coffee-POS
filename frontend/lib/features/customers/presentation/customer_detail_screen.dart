import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/subscription/subscription_action_guard.dart';

import '../application/customer_detail_controller.dart';
import '../application/customer_detail_state.dart';
import '../application/customer_orders_controller.dart';
import '../application/customer_orders_state.dart';
import '../domain/customer_models.dart';
import '../../loyalty/application/customer_loyalty_controller.dart';
import '../../loyalty/application/customer_loyalty_state.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    required this.customerId,
    super.key,
  });

  final int customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen>
    with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _refresh();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref
          .read(customerDetailControllerProvider(widget.customerId).notifier)
          .refresh(),
      ref
          .read(customerOrdersControllerProvider(widget.customerId).notifier)
          .refresh(),
      ref
          .read(customerLoyaltyControllerProvider(widget.customerId).notifier)
          .refresh(),
    ]);
  }

  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Customer'),
          content: const Text(
            'Are you sure you want to delete this customer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final deleted = await ref
        .read(customerDetailControllerProvider(widget.customerId).notifier)
        .deleteCustomer();

    if (!mounted) return;

    if (deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer deleted successfully.'),
        ),
      );
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailState =
        ref.watch(customerDetailControllerProvider(widget.customerId));
    final ordersState =
        ref.watch(customerOrdersControllerProvider(widget.customerId));
    final loyaltyState =
        ref.watch(customerLoyaltyControllerProvider(widget.customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          if (detailState is CustomerDetailLoaded) ...[
            IconButton(
              tooltip: 'Edit customer',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await context.push<bool>(
                  '/customers/${widget.customerId}/edit',
                  extra: detailState,
                );

                if (updated == true && mounted) {
                  await _refresh();
                }
              },
            ),
            IconButton(
              tooltip: 'Delete customer',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteCustomer,
            ),
          ],
        ],
      ),
      body: switch (detailState) {
        CustomerDetailLoading() =>
          const Center(child: CircularProgressIndicator()),
        CustomerDetailError(:final message) => _ErrorView(message: message),
        CustomerDetailLoaded(:final customer) => RefreshIndicator(
            onRefresh: _refresh,
            child: _CustomerDetailContent(
              customer: customer,
              ordersState: ordersState,
              loyaltyState: loyaltyState,
            ),
          ),
      },
    );
  }
}

class _CustomerDetailContent extends StatelessWidget {
  const _CustomerDetailContent({
    required this.customer,
    required this.ordersState,
    required this.loyaltyState,
  });

  final Customer customer;
  final CustomerOrdersState ordersState;
  final CustomerLoyaltyState loyaltyState;

  @override
  Widget build(BuildContext context) {
    final averageOrder = customer.completedOrdersCount == 0
        ? 0.0
        : customer.completedOrdersTotal / customer.completedOrdersCount;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _CustomerHeader(customer: customer),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Orders',
                value: '${customer.completedOrdersCount}',
                icon: Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Total Spent',
                value: '\$${customer.completedOrdersTotal.toStringAsFixed(2)}',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatCard(
          label: 'Average Order',
          value: '\$${averageOrder.toStringAsFixed(2)}',
          icon: Icons.analytics_outlined,
        ),
        const SizedBox(height: 16),
        _LoyaltyCard(
          state: loyaltyState,
          customerId: customer.id,
        ),
        const SizedBox(height: 24),
        const Text(
          'Order History',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        switch (ordersState) {
          CustomerOrdersLoading() =>
            const Center(child: CircularProgressIndicator()),
          CustomerOrdersError(:final message) => Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          CustomerOrdersLoaded(:final orders) => orders.isEmpty
              ? const _EmptyOrders()
              : Column(
                  children:
                      orders.map((order) => _OrderCard(order: order)).toList(),
                ),
        },
      ],
    );
  }
}

class _LoyaltyCard extends ConsumerWidget {
  const _LoyaltyCard({
    required this.state,
    required this.customerId,
  });

  final CustomerLoyaltyState state;
  final int customerId;

  Future<void> _showAdjustmentDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!SubscriptionActionGuard.canModify(ref)) return;

    var pointsText = '';
    var descriptionText = '';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Adjust Loyalty Points'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: (value) => pointsText = value,
                decoration: const InputDecoration(
                  labelText: 'Points',
                  hintText: 'e.g. 50 or -25',
                  helperText: 'Use a negative number to remove points.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                maxLength: 255,
                onChanged: (value) => descriptionText = value,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional reason',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final points = int.tryParse(pointsText.trim());

                if (points == null || points == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a valid non-zero points amount.',
                      ),
                    ),
                  );
                  return;
                }

                final success = await ref
                    .read(
                      customerLoyaltyControllerProvider(customerId).notifier,
                    )
                    .adjustPoints(
                      points: points,
                      description: descriptionText.trim().isEmpty
                          ? null
                          : descriptionText.trim(),
                    );

                if (!dialogContext.mounted) return;

                Navigator.of(dialogContext).pop(success);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!context.mounted || result != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Loyalty points adjusted successfully.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (state) {
          CustomerLoyaltyLoading() => const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading loyalty points...'),
              ],
            ),
          CustomerLoyaltyError(:final message) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.stars_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          CustomerLoyaltyLoaded(:final loyalty) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.stars_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Loyalty',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: SubscriptionActionGuard.canModify(ref)
                          ? () => _showAdjustmentDialog(
                                context,
                                ref,
                              )
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Adjust'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _LoyaltyStat(
                        label: 'Points',
                        value: '${loyalty.account.pointsBalance}',
                      ),
                    ),
                    Expanded(
                      child: _LoyaltyStat(
                        label: 'Lifetime Earned',
                        value: '${loyalty.account.lifetimeEarned}',
                      ),
                    ),
                    Expanded(
                      child: _LoyaltyStat(
                        label: 'Redeemed',
                        value: '${loyalty.account.lifetimeRedeemed}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
        },
      ),
    );
  }
}

class _LoyaltyStat extends StatelessWidget {
  const _LoyaltyStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.customer,
  });

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final name = customer.name.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (customer.phone?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(customer.phone!),
                    ),
                  if (customer.email?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(customer.email!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
  });

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final date = order.completedAt ?? order.createdAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.receipt_long_outlined),
        ),
        title: Text(
          'Order #${order.id}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          [
            order.orderType == 'dine_in' ? 'Dine In' : 'Takeaway',
            if (date != null) _formatDate(date),
          ].join(' • '),
        ),
        trailing: Text(
          '\$${order.total.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text('No completed orders yet.'),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
