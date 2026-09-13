class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class ExpenseUser {
  const ExpenseUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory ExpenseUser.fromJson(Map<String, dynamic> json) {
    return ExpenseUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}

class ExpenseBranch {
  const ExpenseBranch({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory ExpenseBranch.fromJson(Map<String, dynamic> json) {
    return ExpenseBranch(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.branchId,
    required this.expenseCategoryId,
    required this.userId,
    required this.amount,
    required this.description,
    required this.spentAt,
    required this.attachmentPath,
    this.category,
    this.user,
    this.branch,
  });

  final int id;
  final int branchId;
  final int expenseCategoryId;
  final int userId;
  final double amount;
  final String? description;
  final DateTime spentAt;
  final String? attachmentPath;
  final ExpenseCategory? category;
  final ExpenseUser? user;
  final ExpenseBranch? branch;

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as int,
      branchId: json['branch_id'] as int,
      expenseCategoryId: json['expense_category_id'] as int,
      userId: json['user_id'] as int,
      amount: double.parse(json['amount'].toString()),
      description: json['description'] as String?,
      spentAt: DateTime.parse(json['spent_at'].toString()),
      attachmentPath: json['attachment_path'] as String?,
      category: json['category'] is Map<String, dynamic>
          ? ExpenseCategory.fromJson(
              json['category'] as Map<String, dynamic>,
            )
          : null,
      user: json['user'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(
              json['user'] as Map<String, dynamic>,
            )
          : null,
      branch: json['branch'] is Map<String, dynamic>
          ? ExpenseBranch.fromJson(
              json['branch'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class ExpenseListPage {
  const ExpenseListPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<Expense> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  factory ExpenseListPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>;
    final meta = json['meta'] as Map<String, dynamic>;

    return ExpenseListPage(
      data: data
          .map(
            (item) => Expense.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      perPage: meta['per_page'] as int,
      total: meta['total'] as int,
    );
  }
}