import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/orders_list_controller.dart';
import '../application/orders_list_state.dart';
import 'widgets/order_list_tile.dart';

/// Real, API-backed order history screen — replaces the Phase 4
/// placeholder. Reached from the dashboard's "Orders" quick action
/// (unchanged) via the existing `/orders` route (unchanged).
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ordersListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: switch (state) {
        OrdersListLoading() => const Center(child: CircularProgressIndicator()),
        OrdersListError(:final message) => _OrdersErrorView(
            message: message,
            onRetry: () => ref.read(ordersListControllerProvider.notifier).refresh(),
          ),
        OrdersListLoaded loaded =>
          loaded.orders.isEmpty ? const _EmptyOrders() : _OrdersList(state: loaded),
      },
    );
  }
}

class _OrdersList extends ConsumerStatefulWidget {
  const _OrdersList({required this.state});

  final OrdersListLoaded state;

  @override
  ConsumerState<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends ConsumerState<_OrdersList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(ordersListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.state.orders;
    final itemCount = orders.length + (widget.state.hasMore ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () => ref.read(ordersListControllerProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= orders.length) {
            // Footer "load more" spinner — distinct from the initial
            // full-screen loading state.
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final order = orders[index];
          return OrderListTile(
            order: order,
            onTap: () => context.push('/orders/${order.id}'),
          );
        },
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No orders yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Completed sales will show up here',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersErrorView extends StatelessWidget {
  const _OrdersErrorView({required this.message, required this.onRetry});

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
            const SizedBox(height: 12),
            Text('Could not load orders', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
