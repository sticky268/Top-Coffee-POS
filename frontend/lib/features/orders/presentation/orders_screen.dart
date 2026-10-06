import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/orders_list_controller.dart';
import '../application/orders_list_state.dart';
import '../domain/orders_list_filters.dart';
import 'widgets/order_list_tile.dart';
import 'widgets/order_status_helpers.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(OrdersListFilters currentFilters) async {
    final result = await showModalBottomSheet<OrdersListFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OrdersFilterSheet(initialFilters: currentFilters),
    );

    if (!mounted || result == null) return;

    _searchController.text = result.orderNumber ?? '';

    await ref.read(ordersListControllerProvider.notifier).applyFilters(result);
  }

  Future<void> _clearFilters() async {
    _searchController.clear();

    await ref.read(ordersListControllerProvider.notifier).clearFilters();
  }

  void _search() {
    final currentState = ref.read(ordersListControllerProvider);

    final currentFilters = currentState is OrdersListLoaded
        ? currentState.filters
        : OrdersListFilters.empty;

    final searchText = _searchController.text.trim();

    final filters = currentFilters.copyWith(
      orderNumber: searchText,
      clearOrderNumber: searchText.isEmpty,
    );

    ref.read(ordersListControllerProvider.notifier).applyFilters(filters);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(ordersListControllerProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (state) {
        OrdersListLoading() => const Center(child: CircularProgressIndicator()),
        OrdersListError(:final message) => _OrdersErrorView(
          message: message,
          onRetry: () =>
              ref.read(ordersListControllerProvider.notifier).refresh(),
        ),
        OrdersListLoaded loaded => _OrdersContent(
          state: loaded,
          searchController: _searchController,
          onSearch: _search,
          onOpenFilters: () => _openFilters(loaded.filters),
          onClearFilters: loaded.filters.hasFilters ? _clearFilters : null,
        ),
      },
    );
  }
}

class _OrdersContent extends ConsumerStatefulWidget {
  const _OrdersContent({
    required this.state,
    required this.searchController,
    required this.onSearch,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  final OrdersListLoaded state;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback? onClearFilters;

  @override
  ConsumerState<_OrdersContent> createState() => _OrdersContentState();
}

class _OrdersContentState extends ConsumerState<_OrdersContent> {
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
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ordersListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.state.filters;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => widget.onSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search order number...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: widget.searchController.text.isNotEmpty
                        ? pos_ui.IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              widget.searchController.clear();
                              widget.onSearch();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              pos_ui.OutlinedButton.icon(
                onPressed: widget.onOpenFilters,
                icon: const Icon(Icons.tune),
                label: const Text('Filter'),
              ),
            ],
          ),
        ),
        if (filters.hasFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (filters.orderNumber?.trim().isNotEmpty ?? false)
                          _FilterChip(
                            label: 'Order #${filters.orderNumber!.trim()}',
                          ),
                        if (filters.status != null)
                          _FilterChip(label: orderStatusLabel(filters.status!)),
                        if (filters.paymentMethod != null)
                          _FilterChip(
                            label: paymentMethodLabel(filters.paymentMethod!),
                          ),
                        if (filters.dateFrom != null)
                          _FilterChip(
                            label:
                                'From ${DateFormat('MMM d, yyyy').format(filters.dateFrom!)}',
                          ),
                        if (filters.dateTo != null)
                          _FilterChip(
                            label:
                                'To ${DateFormat('MMM d, yyyy').format(filters.dateTo!)}',
                          ),
                      ],
                    ),
                  ),
                ),
                pos_ui.SecondaryButton(
                  onPressed: widget.onClearFilters,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        Expanded(
          child: widget.state.orders.isEmpty
              ? _FilteredEmptyOrders(
                  hasFilters: filters.hasFilters,
                  onClear: widget.onClearFilters,
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(ordersListControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount:
                        widget.state.orders.length +
                        (widget.state.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index >= widget.state.orders.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: widget.state.isLoadingMore
                                ? const CircularProgressIndicator()
                                : const SizedBox.shrink(),
                          ),
                        );
                      }

                      final order = widget.state.orders[index];

                      return OrderListTile(
                        order: order,
                        onTap: () => context.push('/orders/${order.id}'),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(label: Text(label), visualDensity: VisualDensity.compact),
    );
  }
}

class _OrdersFilterSheet extends StatefulWidget {
  const _OrdersFilterSheet({required this.initialFilters});

  final OrdersListFilters initialFilters;

  @override
  State<_OrdersFilterSheet> createState() => _OrdersFilterSheetState();
}

class _OrdersFilterSheetState extends State<_OrdersFilterSheet> {
  late String? _status;
  late String? _paymentMethod;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;

  @override
  void initState() {
    super.initState();

    _status = widget.initialFilters.status;
    _paymentMethod = widget.initialFilters.paymentMethod;
    _dateFrom = widget.initialFilters.dateFrom;
    _dateTo = widget.initialFilters.dateTo;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? _dateFrom ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _dateFrom = picked;

        if (_dateTo != null && _dateTo!.isBefore(picked)) {
          _dateTo = picked;
        }
      } else {
        _dateTo = picked;

        if (_dateFrom != null && _dateFrom!.isAfter(picked)) {
          _dateFrom = picked;
        }
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      OrdersListFilters(
        orderNumber: widget.initialFilters.orderNumber,
        status: _status,
        paymentMethod: _paymentMethod,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      ),
    );
  }

  void _clear() {
    setState(() {
      _status = null;
      _paymentMethod = null;
      _dateFrom = null;
      _dateTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filter Orders',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ...[
                    'held',
                    'new',
                    'preparing',
                    'ready',
                    'completed',
                    'cancelled',
                  ].map(
                    (status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(orderStatusLabel(status)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _status = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All payment methods'),
                  ),
                  ...['cash', 'card', 'qr', 'split'].map(
                    (method) => DropdownMenuItem<String>(
                      value: method,
                      child: Text(paymentMethodLabel(method)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Date range',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: pos_ui.OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: true),
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _dateFrom == null
                            ? 'From date'
                            : DateFormat('MMM d, yyyy').format(_dateFrom!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: pos_ui.OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: false),
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _dateTo == null
                            ? 'To date'
                            : DateFormat('MMM d, yyyy').format(_dateTo!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: pos_ui.OutlinedButton(
                      onPressed: _clear,
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: pos_ui.PrimaryButton(
                      onPressed: _apply,
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilteredEmptyOrders extends StatelessWidget {
  const _FilteredEmptyOrders({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters
                  ? Icons.search_off_outlined
                  : Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters ? 'No matching orders' : 'No orders yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters
                  ? 'Try changing your search or filters'
                  : 'Completed sales will show up here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasFilters && onClear != null) ...[
              const SizedBox(height: 16),
              pos_ui.OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear Filters'),
              ),
            ],
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
            const SizedBox(height: 16),
            Text('Could not load orders', style: theme.textTheme.titleMedium),
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
