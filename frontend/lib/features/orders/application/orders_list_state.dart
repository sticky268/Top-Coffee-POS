import '../domain/order_models.dart';

sealed class OrdersListState {
  const OrdersListState();
}

class OrdersListLoading extends OrdersListState {
  const OrdersListLoading();
}

class OrdersListLoaded extends OrdersListState {
  const OrdersListLoaded({
    required this.orders,
    required this.currentPage,
    required this.lastPage,
    this.isLoadingMore = false,
  });

  final List<OrderSummary> orders;
  final int currentPage;
  final int lastPage;

  /// True while a loadMore() request is in flight — drives the footer
  /// spinner in the list, distinct from the initial full-screen loading
  /// state.
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  OrdersListLoaded copyWith({
    List<OrderSummary>? orders,
    int? currentPage,
    int? lastPage,
    bool? isLoadingMore,
  }) {
    return OrdersListLoaded(
      orders: orders ?? this.orders,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class OrdersListError extends OrdersListState {
  const OrdersListError(this.message);
  final String message;
}
