import '../domain/expense_models.dart';

sealed class ExpenseCategoriesState {
  const ExpenseCategoriesState();
}

class ExpenseCategoriesLoading extends ExpenseCategoriesState {
  const ExpenseCategoriesLoading();
}

class ExpenseCategoriesLoaded extends ExpenseCategoriesState {
  const ExpenseCategoriesLoaded(this.categories);

  final List<ExpenseCategory> categories;
}

class ExpenseCategoriesError extends ExpenseCategoriesState {
  const ExpenseCategoriesError(this.message);

  final String message;
}