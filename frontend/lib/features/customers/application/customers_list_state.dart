import '../domain/customer_models.dart';

sealed class CustomersListState {
  const CustomersListState();
}

class CustomersListLoading extends CustomersListState {
  const CustomersListLoading();
}

class CustomersListLoaded extends CustomersListState {
  const CustomersListLoaded({
    required this.customers,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<Customer> customers;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  CustomersListLoaded copyWith({
    List<Customer>? customers,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return CustomersListLoaded(
      customers: customers ?? this.customers,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class CustomersListError extends CustomersListState {
  const CustomersListError(this.message);

  final String message;
}
