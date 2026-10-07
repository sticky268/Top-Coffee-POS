import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/kds_controller.dart';
import '../application/kds_state.dart';
import '../domain/kds_models.dart';

class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen> {
  Timer? _refreshTimer;
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadForCurrentBranch(),
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadForCurrentBranch();
      _startAutoRefresh();
    });
  }

  void _loadForCurrentBranch() {
    final branchId = ref.read(currentBranchProvider)?.id;

    ref.read(kdsControllerProvider.notifier).loadTickets(branchId: branchId);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kdsControllerProvider);
    final branch = ref.watch(currentBranchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Display'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading ? null : _loadForCurrentBranch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadForCurrentBranch();

          while (ref.read(kdsControllerProvider).isLoading) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        },
        child: _buildBody(context, state, branch?.name),
      ),
    );
  }

  Widget _buildBody(BuildContext context, KdsState state, String? branchName) {
    if (state.isLoading && state.tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.tickets.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Unable to load kitchen tickets.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(state.errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          pos_ui.PrimaryButton(
            onPressed: _loadForCurrentBranch,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final newTickets = _ticketsForStatus(state.tickets, 'new');
    final preparingTickets = _ticketsForStatus(state.tickets, 'preparing');
    final readyTickets = _ticketsForStatus(state.tickets, 'ready');
    final completedTickets = _ticketsForStatus(state.tickets, 'completed');
    final cancelledTickets = _ticketsForStatus(state.tickets, 'cancelled');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (branchName != null) ...[
          Text(branchName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
        ],
        if (cancelledTickets.isNotEmpty) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${cancelledTickets.length} CANCELLED kitchen ticket(s) — stop preparation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'CANCELLED — DO NOT PREPARE',
            tickets: cancelledTickets,
            emptyText: 'No cancelled tickets',
          ),
          const SizedBox(height: 24),
        ],
        _buildSection(
          context,
          title: 'NEW',
          tickets: newTickets,
          emptyText: 'No new orders',
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'PREPARING',
          tickets: preparingTickets,
          emptyText: 'Nothing is being prepared',
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'READY',
          tickets: readyTickets,
          emptyText: 'No orders ready',
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'COMPLETED',
          tickets: completedTickets,
          emptyText: 'No completed orders',
        ),
      ],
    );
  }

  List<KitchenTicket> _ticketsForStatus(
    List<KitchenTicket> tickets,
    String status,
  ) {
    return tickets.where((ticket) {
      final effectiveStatus = ticket.order.status == 'cancelled'
          ? 'cancelled'
          : ticket.status;
      return effectiveStatus == status;
    }).toList();
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<KitchenTicket> tickets,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 12,
              child: Text(
                tickets.length.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tickets.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyText),
            ),
          )
        else
          ...tickets.map(
            (ticket) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: KdsTicketCard(ticket: ticket),
            ),
          ),
      ],
    );
  }
}

class KdsTicketCard extends ConsumerWidget {
  const KdsTicketCard({required this.ticket, super.key});

  final KitchenTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kdsControllerProvider);
    final isUpdating = state.updatingTicketId == ticket.id;
    final isCancelled = ticket.status == 'cancelled' ||
        ticket.order.status == 'cancelled';

    final nextStatus = switch (ticket.status) {
      'new' => 'preparing',
      'preparing' => 'ready',
      'ready' => 'completed',
      _ => null,
    };

    final buttonText = switch (ticket.status) {
      'new' => 'START PREPARING',
      'preparing' => 'MARK READY',
      'ready' => 'COMPLETE',
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${ticket.order.id}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (ticket.order.table != null)
                  Chip(label: Text(ticket.order.table!.name)),
              ],
            ),
            if (isCancelled) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'CANCELLED — STOP PREPARATION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatOrderType(ticket.order.orderType),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            ...ticket.order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        _formatQuantity(item.quantity),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName),
                          if (item.variantName != null)
                            Text(
                              item.variantName!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (item.notes?.trim().isNotEmpty ?? false)
                            Text(
                              'Note: ${item.notes}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isCancelled) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: pos_ui.PrimaryButton(
                  onPressed: isUpdating
                      ? null
                      : () async {
                          try {
                            await ref
                                .read(kdsControllerProvider.notifier)
                                .acknowledgeCancellation(ticketId: ticket.id);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not acknowledge cancellation. Please retry.'),
                                ),
                              );
                            }
                          }
                        },
                  isLoading: isUpdating,
                  child: const Text('ACKNOWLEDGE CANCELLATION'),
                ),
              ),
            ],
            if (!isCancelled && nextStatus != null && buttonText != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: pos_ui.PrimaryButton(
                  onPressed: isUpdating
                      ? null
                      : () {
                          ref
                              .read(kdsControllerProvider.notifier)
                              .updateStatus(
                                ticketId: ticket.id,
                                status: nextStatus,
                              );
                        },
                  isLoading: isUpdating,
                  child: Text(buttonText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatOrderType(String value) {
    switch (value) {
      case 'dine_in':
        return 'Dine In';
      case 'takeaway':
        return 'Takeaway';
      case 'delivery':
        return 'Delivery';
      default:
        return value;
    }
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }
}
