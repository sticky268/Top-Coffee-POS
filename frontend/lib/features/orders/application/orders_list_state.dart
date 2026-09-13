import '../domain/order_models.dart';
import '../domain/orders_list_filters.dart';

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
    this.filters = OrdersListFilters.empty,
    this.isLoadingMore = false,
  });

  final List<OrderSummary> orders;
  final int currentPage;
  final int lastPage;
  final OrdersListFilters filters;

  /// True while a loadMore() request is in flight — drives the footer
  /// spinner in the list, distinct from the initial full-screen loading
  /// state.
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  OrdersListLoaded copyWith({
    List<OrderSummary>? orders,
    int? currentPage,
    int? lastPage,
    OrdersListFilters? filters,
    bool? isLoadingMore,
  }) {
    return OrdersListLoaded(
      orders: orders ?? this.orders,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      filters: filters ?? this.filters,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class OrdersListError extends OrdersListState {
  const OrdersListError(this.message);

  final String message;
}
