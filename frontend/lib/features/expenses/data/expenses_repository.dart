import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../../../core/network/api_client.dart';
import '../domain/expense_models.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(apiClientProvider));
});

class ExpensesRepository {
  ExpensesRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ExpenseCategory>> getExpenseCategories() async {
    final response = await _apiClient.request(
      (dio) => dio.get('/expense-categories'),
    );

    final data = response.data['data'] as List<dynamic>;

    return data
        .map(
          (item) => ExpenseCategory.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }
  Future<ExpenseListPage> getExpenses({
    int? categoryId,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/expenses',
        queryParameters: {
          if (categoryId != null) 'category_id': categoryId,
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'per_page': perPage,
        },
      ),
    );

    return ExpenseListPage.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ExpenseSummary> getExpenseSummary() async {
    final response = await _apiClient.request(
      (dio) => dio.get('/expenses/summary'),
    );

    return ExpenseSummary.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
  Future<Expense> getExpense(int id) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/expenses/$id'),
    );

    return Expense.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Expense> createExpense({
    required int categoryId,
    required double amount,
    String? description,
    required String spentAt,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/expenses',
        data: {
          'category_id': categoryId,
          'amount': amount,
          'description': description,
          'spent_at': spentAt,
        },
      ),
    );

    return Expense.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<Expense> updateExpense({
    required int id,
    int? categoryId,
    double? amount,
    String? description,
    String? spentAt,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/expenses/$id',
        data: {
          if (categoryId != null) 'category_id': categoryId,
          if (amount != null) 'amount': amount,
          if (description != null) 'description': description,
          if (spentAt != null) 'spent_at': spentAt,
        },
      ),
    );

    return Expense.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }
  Future<void> deleteExpense(int id) async {
    await _apiClient.request(
      (dio) => dio.delete('/expenses/$id'),
    );
  }
}