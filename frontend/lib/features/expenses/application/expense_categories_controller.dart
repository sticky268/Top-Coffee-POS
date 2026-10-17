import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/expenses_repository.dart';
import 'expense_categories_state.dart';

class ExpenseCategoriesController
    extends StateNotifier<ExpenseCategoriesState> {
  int _generation = 0;
  ExpenseCategoriesController(this._repository)
      : super(const ExpenseCategoriesLoading());

  final ExpensesRepository _repository;

  Future<void> load() async {
    final generation = ++_generation;
    state = const ExpenseCategoriesLoading();

    try {
      final categories = await _repository.getExpenseCategories();
      if (!mounted || generation != _generation) return;
      state = ExpenseCategoriesLoaded(categories);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = ExpenseCategoriesError(error.toString());
    }
  }
}

final expenseCategoriesControllerProvider =
    StateNotifierProvider<ExpenseCategoriesController,
        ExpenseCategoriesState>((ref) {
  return ExpenseCategoriesController(
    ref.watch(expensesRepositoryProvider),
  );
});