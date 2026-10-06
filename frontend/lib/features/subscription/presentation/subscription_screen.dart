import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/subscription_controller.dart';
import '../application/subscription_state.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref
                  .read(subscriptionControllerProvider.notifier)
                  .refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (state) {
        SubscriptionLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        SubscriptionError(:final message) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(subscriptionControllerProvider.notifier)
                          .refresh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        SubscriptionLoaded(:final subscription) => _SubscriptionContent(
            subscription: subscription,
          ),
      },
    );
  }
}

class _SubscriptionContent extends StatelessWidget {
  const _SubscriptionContent({
    required this.subscription,
  });

  final dynamic subscription;

  @override
  Widget build(BuildContext context) {
    final plan = subscription.plan;
    final branchUsage = subscription.branchUsage;
    final status = subscription.subscription;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (subscription.isReadOnly)
          Card(
            child: ListTile(
              leading: Icon(
                status.isSuspended
                    ? Icons.pause_circle_outline
                    : Icons.warning_amber_rounded,
              ),
              title: Text(
                status.isSuspended
                    ? 'Subscription suspended'
                    : 'Subscription expired',
              ),
              subtitle: const Text(
                'The account is read-only until the subscription is restored.',
              ),
            ),
          ),
        if (subscription.isReadOnly) const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Plan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  plan?.name ?? 'No plan',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (plan != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_formatPrice(plan.price)} / ${plan.billingInterval}',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Branch Usage'),
            subtitle: Text(
              '${branchUsage.current} / ${branchUsage.limit?.toString() ?? 'Unlimited'} branches',
            ),
            trailing: branchUsage.remaining == null
                ? null
                : Text(
                    '${branchUsage.remaining} left',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.circle),
                title: const Text('Status'),
                trailing: Text(_formatStatus(status.status)),
              ),
              if (status.startedAt != null)
                ListTile(
                  leading: const Icon(Icons.play_arrow_outlined),
                  title: const Text('Started'),
                  trailing: Text(_formatDate(status.startedAt)),
                ),
              if (status.expiresAt != null)
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Expires'),
                  trailing: Text(_formatDate(status.expiresAt)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatPrice(double price) {
    return '\$${price.toStringAsFixed(2)}';
  }

  static String _formatStatus(String status) {
    switch (status) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Active';
      case 'expired':
        return 'Expired';
      case 'suspended':
        return 'Suspended';
      default:
        return status;
    }
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}