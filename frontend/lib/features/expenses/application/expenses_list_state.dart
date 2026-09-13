import '../domain/expense_models.dart';

sealed class ExpensesListState {
  const ExpensesListState();
}

class ExpensesListLoading extends ExpensesListState {
  const ExpensesListLoading();
}

class ExpensesListLoaded extends ExpensesListState {
  const ExpensesListLoaded({
    required this.expenses,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<Expense> expenses;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  ExpensesListLoaded copyWith({
    List<Expense>? expenses,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return ExpensesListLoaded(
      expenses: expenses ?? this.expenses,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class ExpensesListError extends ExpensesListState {
  const ExpensesListError(this.message);

  final String message;
}