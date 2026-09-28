import '../domain/customer_models.dart';

sealed class CustomerOrdersState {
  const CustomerOrdersState();
}

class CustomerOrdersLoading extends CustomerOrdersState {
  const CustomerOrdersLoading();
}

class CustomerOrdersLoaded extends CustomerOrdersState {
  const CustomerOrdersLoaded({
    required this.orders,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<CustomerOrder> orders;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  CustomerOrdersLoaded copyWith({
    List<CustomerOrder>? orders,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return CustomerOrdersLoaded(
      orders: orders ?? this.orders,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class CustomerOrdersError extends CustomerOrdersState {
  const CustomerOrdersError(this.message);

  final String message;
}
