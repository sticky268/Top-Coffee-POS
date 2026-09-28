import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../application/expense_summary_controller.dart';
import '../application/expense_summary_state.dart';
import '../application/expense_categories_controller.dart';
import '../application/expense_categories_state.dart';
import '../application/expenses_list_controller.dart';
import '../application/expenses_list_state.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_models.dart';
import 'add_expense_screen.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _searchController = TextEditingController();

  int? _categoryId;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(expenseCategoriesControllerProvider.notifier).load();
      ref.read(expenseSummaryControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshExpenses() async {
    await Future.wait([
      ref.read(expensesListControllerProvider.notifier).refresh(),
      ref.read(expenseSummaryControllerProvider.notifier).refresh(),
    ]);
  }
  Future<void> _search() async {
    await ref.read(expensesListControllerProvider.notifier).applyFilters(
          search: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
        );
  }

  Future<void> _openAddExpense() async {
    final created = await context.push<bool>('/expenses/add');

    if (created == true && mounted) {
      await _refreshExpenses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expensesListControllerProvider);
    final summaryState = ref.watch(expenseSummaryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expenses',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          FilledButton.icon(
            onPressed: _openAddExpense,
            icon: const Icon(Icons.add),
            label: const Text('Add Expense'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshExpenses,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (state) {
        ExpensesListLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        ExpensesListError(:final message) => _ExpensesErrorView(
            message: message,
            onRetry: _refreshExpenses,
          ),
        ExpensesListLoaded loaded => _ExpensesContent(
            state: loaded,
            summaryState: summaryState,
            onRefresh: _refreshExpenses,
            searchController: _searchController,
            onSearch: _search,
            categoryId: _categoryId,
            dateFrom: _dateFrom,
            dateTo: _dateTo,
            onCategoryChanged: (value) {
              setState(() {
                _categoryId = value;
              });
            },
            onDateRangeChanged: (from, to) {
              setState(() {
                _dateFrom = from;
                _dateTo = to;
              });
            },
            onClearFilters: () {
              setState(() {
                _categoryId = null;
                _dateFrom = null;
                _dateTo = null;
              });
            },
          ),
      },
    );
  }
}

class _ExpensesContent extends ConsumerStatefulWidget {
  const _ExpensesContent({
    required this.state,
    required this.summaryState,
    required this.onRefresh,
    required this.searchController,
    required this.onSearch,
    required this.categoryId,
    required this.dateFrom,
    required this.dateTo,
    required this.onCategoryChanged,
    required this.onDateRangeChanged,
    required this.onClearFilters,
  });

  final ExpensesListLoaded state;
  final ExpenseSummaryState summaryState;
  final Future<void> Function() onRefresh;
  final TextEditingController searchController;
  final VoidCallback onSearch;

  final int? categoryId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ValueChanged<int?> onCategoryChanged;
  final void Function(DateTime? from, DateTime? to) onDateRangeChanged;
  final VoidCallback onClearFilters;

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

  Future<void> _applyFilters() async {
    await ref.read(expensesListControllerProvider.notifier).applyFilters(
          categoryId: widget.categoryId,
          dateFrom: widget.dateFrom == null
              ? null
              : DateFormat('yyyy-MM-dd').format(widget.dateFrom!),
          dateTo: widget.dateTo == null
              ? null
              : DateFormat('yyyy-MM-dd').format(widget.dateTo!),
          search: widget.searchController.text.trim().isEmpty
              ? null
              : widget.searchController.text.trim(),
        );
  }

  Future<void> _clearFilters() async {
    setState(() {
      widget.onCategoryChanged(null);
      widget.onDateRangeChanged(null, null);
      
      widget.searchController.clear();
    });

    await ref.read(expensesListControllerProvider.notifier).clearFilters();
  }

  Future<void> _selectCategory() async {
    final categoryState =
        ref.read(expenseCategoriesControllerProvider);

    if (categoryState is! ExpenseCategoriesLoaded) return;

    final selected = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Expense Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.apps_outlined),
                title: const Text('All categories'),
                trailing: widget.categoryId == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, null),
              ),
              ...categoryState.categories.map(
                (category) => ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(category.name),
                  trailing: widget.categoryId == category.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, category.id),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    setState(() {
      widget.onCategoryChanged(selected);
    });

    await _applyFilters();
  }

  Future<void> _selectDateRange() async {
    final initialStart = widget.dateFrom ?? DateTime.now();
    final initialEnd = widget.dateTo ?? initialStart;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: initialStart.isAfter(initialEnd) ? initialEnd : initialStart,
        end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
      ),
    );

    if (range == null || !mounted) return;

    setState(() {
      widget.onDateRangeChanged(range.start, range.end);
      
    });

    await _applyFilters();
  }

  Future<void> _editExpense(Expense expense) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(expense: expense),
      ),
    );

    if (updated == true && mounted) {
      await widget.onRefresh();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete expense?'),
          content: Text(
            'Delete this ${expense.category?.name ?? 'expense'} '
            'for \$${expense.amount.toStringAsFixed(2)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(expensesRepositoryProvider).deleteExpense(expense.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense deleted successfully.'),
        ),
      );

      await widget.onRefresh();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete expense: $error'),
        ),
      );
    }
  }

  double get _visibleTotal {
    return widget.state.expenses.fold(
      0,
      (total, expense) => total + expense.amount,
    );
  }

  bool get _hasFilters {
    return widget.categoryId != null ||
        widget.dateFrom != null ||
        widget.dateTo != null ||
        widget.searchController.text.trim().isNotEmpty;
  }

  String? _getCategoryName() {
    final categoryState =
        ref.read(expenseCategoriesControllerProvider);

    if (widget.categoryId == null ||
        categoryState is! ExpenseCategoriesLoaded) {
      return null;
    }

    for (final category in categoryState.categories) {
      if (category.id == widget.categoryId) {
        return category.name;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _ExpenseDashboard(
                summaryState: widget.summaryState,
                filteredTotal: _visibleTotal,
                filteredCount: widget.state.expenses.length,
                totalCount: widget.state.total,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _FilterSection(
                searchController: widget.searchController,
                onSearch: widget.onSearch,
                onCategoryTap: _selectCategory,
                onDateTap: _selectDateRange,
                onClear: _clearFilters,
                categoryId: widget.categoryId,
                categoryName: _getCategoryName(),
                dateFrom: widget.dateFrom,
                dateTo: widget.dateTo,
                hasFilters: _hasFilters,
              ),
            ),
          ),
          if (widget.state.expenses.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyExpenses(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList.separated(
                itemCount: widget.state.expenses.length +
                    (widget.state.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index >= widget.state.expenses.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: widget.state.isLoadingMore
                            ? const CircularProgressIndicator()
                            : const SizedBox.shrink(),
                      ),
                    );
                  }

                  final expense = widget.state.expenses[index];

                  return _ExpenseCard(
                    expense: expense,
                    onEdit: () => _editExpense(expense),
                    onDelete: () => _deleteExpense(expense),
                  );
                },
              ),
            ),
          if (widget.state.expenses.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    '${widget.state.expenses.length} of ${widget.state.total} expenses shown',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseDashboard extends StatelessWidget {
  const _ExpenseDashboard({
    required this.summaryState,
    required this.filteredTotal,
    required this.filteredCount,
    required this.totalCount,
  });

  final ExpenseSummaryState summaryState;
  final double filteredTotal;
  final int filteredCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return switch (summaryState) {
      ExpenseSummaryLoading() => const _DashboardLoading(),
      ExpenseSummaryError(:final message) => _DashboardError(
          message: message,
        ),
      ExpenseSummaryLoaded(:final summary) => _DashboardLoaded(
          summary: summary,
          filteredTotal: filteredTotal,
          filteredCount: filteredCount,
          totalCount: totalCount,
        ),
    };
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardLoaded extends StatelessWidget {
  const _DashboardLoaded({
    required this.summary,
    required this.filteredTotal,
    required this.filteredCount,
    required this.totalCount,
  });

  final ExpenseSummary summary;
  final double filteredTotal;
  final int filteredCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardPeriodCards(summary: summary),
        const SizedBox(height: 12),
        _DashboardComparisons(summary: summary),
        const SizedBox(height: 12),
        _DashboardTrend(summary: summary),
        const SizedBox(height: 12),
        _DashboardCategories(summary: summary),
        if (filteredCount != totalCount) ...[
          const SizedBox(height: 12),
          _FilteredResultsCard(
            total: filteredTotal,
            count: filteredCount,
            totalCount: totalCount,
          ),
        ],
      ],
    );
  }
}

class _DashboardPeriodCards extends StatelessWidget {
  const _DashboardPeriodCards({
    required this.summary,
  });

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        final cards = [
          _PeriodCard(
            icon: Icons.today_outlined,
            label: 'Today',
            amount: summary.today,
          ),
          _PeriodCard(
            icon: Icons.date_range_outlined,
            label: 'This Week',
            amount: summary.week,
          ),
          _PeriodCard(
            icon: Icons.calendar_month_outlined,
            label: 'This Month',
            amount: summary.month,
          ),
        ];

        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.icon,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '\$${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
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

class _DashboardComparisons extends StatelessWidget {
  const _DashboardComparisons({
    required this.summary,
  });

  final ExpenseSummary summary;

  String _comparisonText(
    double current,
    double previous,
    String period,
  ) {
    final difference = current - previous;

    if (difference == 0) {
      return 'Same as previous $period.';
    }

    final amount = '\$${difference.abs().toStringAsFixed(2)}';

    if (difference > 0) {
      return 'Spending increased by $amount compared with previous $period.';
    }

    return 'Spending decreased by $amount compared with previous $period.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spending comparison',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _comparisonText(
                summary.week,
                summary.previousWeek,
                'week',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _comparisonText(
                summary.month,
                summary.previousMonth,
                'month',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTrend extends StatelessWidget {
  const _DashboardTrend({
    required this.summary,
  });

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (summary.trend.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxAmount = summary.trend
        .map((point) => point.amount)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spending trend',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in summary.trend)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _TrendBar(
                          point: point,
                          maxAmount: maxAmount,
                        ),
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

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.point,
    required this.maxAmount,
  });

  final ExpenseTrendPoint point;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final height = maxAmount <= 0
        ? 4.0
        : 12.0 + ((point.amount / maxAmount) * 88.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          point.amount == 0
              ? '\$0'
              : '\$${point.amount.toStringAsFixed(0)}',
          style: theme.textTheme.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          point.day,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DashboardCategories extends StatelessWidget {
  const _DashboardCategories({
    required this.summary,
  });

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (summary.categories.isEmpty) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No category spending recorded this month.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final maxAmount = summary.categories
        .map((category) => category.amount)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expense by category',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < summary.categories.length; i++) ...[
              _CategoryExpenseRow(
                category: summary.categories[i],
                maxAmount: maxAmount,
              ),
              if (i < summary.categories.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryExpenseRow extends StatelessWidget {
  const _CategoryExpenseRow({
    required this.category,
    required this.maxAmount,
  });

  final ExpenseCategorySummary category;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fraction = maxAmount <= 0
        ? 0.0
        : (category.amount / maxAmount).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category.categoryName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '\$${category.amount.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
          ),
        ),
      ],
    );
  }
}

class _FilteredResultsCard extends StatelessWidget {
  const _FilteredResultsCard({
    required this.total,
    required this.count,
    required this.totalCount,
  });

  final double total;
  final int count;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.filter_alt_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtered results',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count of $totalCount expenses shown',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '\$${total.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _FilterSection extends StatefulWidget {
  const _FilterSection({
    required this.searchController,
    required this.onSearch,
    required this.onCategoryTap,
    required this.onDateTap,
    required this.onClear,
    required this.categoryId,
    required this.categoryName,
    required this.dateFrom,
    required this.dateTo,
    required this.hasFilters,
  });

  final TextEditingController searchController;
  final VoidCallback onSearch;
  final VoidCallback onCategoryTap;
  final VoidCallback onDateTap;
  final VoidCallback onClear;
  final int? categoryId;
  final String? categoryName;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool hasFilters;

  @override
  State<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends State<_FilterSection> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant _FilterSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_onSearchChanged);
      widget.searchController.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String dateLabel = 'Date range';

    if (widget.dateFrom != null && widget.dateTo != null) {
      dateLabel =
          '${DateFormat('MMM d').format(widget.dateFrom!)} - ${DateFormat('MMM d, yyyy').format(widget.dateTo!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
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
                    },
                    icon: const Icon(Icons.clear),
                  )
                : null,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onCategoryTap,
              icon: const Icon(
                Icons.category_outlined,
                size: 18,
              ),
              label: Text(
                widget.categoryName ?? 'Category',
              ),
            ),
            OutlinedButton.icon(
              onPressed: widget.onDateTap,
              icon: const Icon(
                Icons.date_range_outlined,
                size: 18,
              ),
              label: Text(dateLabel),
            ),
            if (widget.hasFilters)
              TextButton.icon(
                onPressed: widget.onClear,
                icon: const Icon(
                  Icons.clear_all,
                  size: 18,
                ),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (widget.hasFilters)
          Text(
            'Filters applied',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('MMM d, yyyy').format(expense.spentAt.toLocal());

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          expense.category?.name ?? 'Uncategorized',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${expense.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (expense.description?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 5),
                    Text(
                      expense.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _MetaItem(
                        icon: Icons.calendar_today_outlined,
                        text: date,
                      ),
                      if (expense.user != null)
                        _MetaItem(
                          icon: Icons.person_outline,
                          text: expense.user!.name,
                        ),
                      if (expense.branch != null)
                        _MetaItem(
                          icon: Icons.storefront_outlined,
                          text: expense.branch!.name,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                      ),
                    ],
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

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No expenses found',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try changing your filters or add a new expense.',
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
              size: 44,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load expenses',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
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