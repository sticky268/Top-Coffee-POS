import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/expenses_repository.dart';
import 'expenses_list_state.dart';

/// Loads and manages the expense list.
class ExpensesListController extends StateNotifier<ExpensesListState> {
  ExpensesListController(this._repository, this._ref)
      : super(const ExpensesListLoading()) {
    _branchId = _ref.read(currentBranchProvider)?.id;

    _ref.listen(
      currentBranchProvider,
      (_, next) {
        final nextBranchId = next?.id;

        if (_branchId == nextBranchId) {
          return;
        }

        _branchId = nextBranchId;
        refresh();
      },
    );

    _initialization = _load();
  }

  final ExpensesRepository _repository;
  final Ref _ref;

  int? _branchId;

  int? _categoryId;
  String? _dateFrom;
  String? _dateTo;
  String? _search;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> applyFilters({
    int? categoryId,
    String? dateFrom,
    String? dateTo,
    String? search,
  }) {
    _categoryId = categoryId;
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    _search = search;

    return refresh();
  }

  Future<void> clearFilters() {
    _categoryId = null;
    _dateFrom = null;
    _dateTo = null;
    _search = null;

    return refresh();
  }

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const ExpensesListLoading();

    try {
      final page = await _repository.getExpenses(
        categoryId: _categoryId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        search: _search,
        page: 1,
      );

      if (!mounted) return;

      state = ExpensesListLoaded(
        expenses: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;

      state = ExpensesListError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! ExpensesListLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = await _repository.getExpenses(
        categoryId: _categoryId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        search: _search,
        page: current.currentPage + 1,
      );

      if (!mounted) return;

      final latest = state;

      if (latest is! ExpensesListLoaded) return;

      state = latest.copyWith(
        expenses: [...latest.expenses, ...nextPage.data],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        total: nextPage.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;

      final latest = state;

      if (latest is ExpensesListLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}

final expensesListControllerProvider =
    StateNotifierProvider<ExpensesListController, ExpensesListState>((ref) {
  return ExpensesListController(
    ref.watch(expensesRepositoryProvider),
    ref,
  );
});