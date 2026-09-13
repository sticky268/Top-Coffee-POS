import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/expenses_repository.dart';
import 'expense_categories_state.dart';

class ExpenseCategoriesController
    extends StateNotifier<ExpenseCategoriesState> {
  ExpenseCategoriesController(this._repository)
      : super(const ExpenseCategoriesLoading());

  final ExpensesRepository _repository;

  Future<void> load() async {
    state = const ExpenseCategoriesLoading();

    try {
      final categories = await _repository.getExpenseCategories();
      state = ExpenseCategoriesLoaded(categories);
    } catch (error) {
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