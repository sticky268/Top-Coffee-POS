import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/expenses_repository.dart';
import 'expense_summary_state.dart';

class ExpenseSummaryController
    extends StateNotifier<ExpenseSummaryState> {
  ExpenseSummaryController(this._repository, this._ref)
      : super(const ExpenseSummaryLoading()) {
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

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const ExpenseSummaryLoading();

    try {
      final summary = await _repository.getExpenseSummary();

      if (!mounted) return;

      state = ExpenseSummaryLoaded(summary);
    } catch (e) {
      if (!mounted) return;

      state = ExpenseSummaryError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }
}

final expenseSummaryControllerProvider =
    StateNotifierProvider<ExpenseSummaryController,
        ExpenseSummaryState>((ref) {
  return ExpenseSummaryController(
    ref.watch(expensesRepositoryProvider),
    ref,
  );
});