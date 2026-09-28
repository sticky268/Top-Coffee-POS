import '../domain/expense_models.dart';

sealed class ExpenseSummaryState {
  const ExpenseSummaryState();
}

class ExpenseSummaryLoading extends ExpenseSummaryState {
  const ExpenseSummaryLoading();
}

class ExpenseSummaryLoaded extends ExpenseSummaryState {
  const ExpenseSummaryLoaded(this.summary);

  final ExpenseSummary summary;
}

class ExpenseSummaryError extends ExpenseSummaryState {
  const ExpenseSummaryError(this.message);

  final String message;
}