import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../application/expenses_list_controller.dart';
import '../application/expenses_list_state.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    ref.read(expensesListControllerProvider.notifier).applyFilters(
          search: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expensesListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
            FilledButton.icon(
              onPressed: () async {
                final created = await context.push<bool>('/expenses/add');

                if (created == true && mounted) {
                  ref
                      .read(expensesListControllerProvider.notifier)
                      .refresh();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
            ),
            const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(expensesListControllerProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (state) {
        ExpensesListLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        ExpensesListError(:final message) => _ExpensesErrorView(
            message: message,
            onRetry: () => ref
                .read(expensesListControllerProvider.notifier)
                .refresh(),
          ),
        ExpensesListLoaded loaded => _ExpensesContent(
            state: loaded,
            searchController: _searchController,
            onSearch: _search,
          ),
      },
    );
  }
}

class _ExpensesContent extends ConsumerStatefulWidget {
  const _ExpensesContent({
    required this.state,
    required this.searchController,
    required this.onSearch,
  });

  final ExpensesListLoaded state;
  final TextEditingController searchController;
  final VoidCallback onSearch;

  @override
  ConsumerState<_ExpensesContent> createState() => _ExpensesContentState();
}

class _ExpensesContentState extends ConsumerState<_ExpensesContent> {
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
      ref.read(expensesListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: widget.searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => widget.onSearch(),
            decoration: InputDecoration(
              hintText: 'Search expenses...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        widget.searchController.clear();
                        widget.onSearch();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: widget.state.expenses.isEmpty
              ? const _EmptyExpenses()
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(expensesListControllerProvider.notifier)
                      .refresh(),
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: widget.state.expenses.length +
                        (widget.state.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index >= widget.state.expenses.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: widget.state.isLoadingMore
                                ? const CircularProgressIndicator()
                                : const SizedBox.shrink(),
                          ),
                        );
                      }

                      final expense = widget.state.expenses[index];

                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long_outlined),
                        ),
                        title: Text(
                          expense.category?.name ?? 'Uncategorized',
                        ),
                        subtitle: Text(
                          [
                            if (expense.description?.isNotEmpty ?? false)
                              expense.description!,
                            DateFormat('MMM d, yyyy')
                                .format(expense.spentAt.toLocal()),
                          ].join(' • '),
                        ),
                        trailing: Text(
                          '\$${expense.amount.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses();

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
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No expenses yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Expenses you record will show up here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpensesErrorView extends StatelessWidget {
  const _ExpensesErrorView({
    required this.message,
    required this.onRetry,
  });

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
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load expenses',
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
