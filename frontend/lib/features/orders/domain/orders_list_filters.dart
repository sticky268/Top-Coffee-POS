class OrdersListFilters {
  const OrdersListFilters({
    this.orderNumber,
    this.status,
    this.paymentMethod,
    this.dateFrom,
    this.dateTo,
  });

  final String? orderNumber;
  final String? status;
  final String? paymentMethod;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  bool get hasFilters =>
      (orderNumber?.trim().isNotEmpty ?? false) ||
      status != null ||
      paymentMethod != null ||
      dateFrom != null ||
      dateTo != null;

  OrdersListFilters copyWith({
    String? orderNumber,
    String? status,
    String? paymentMethod,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearOrderNumber = false,
    bool clearStatus = false,
    bool clearPaymentMethod = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
  }) {
    return OrdersListFilters(
      orderNumber:
          clearOrderNumber ? null : (orderNumber ?? this.orderNumber),
      status: clearStatus ? null : (status ?? this.status),
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
    );
  }

  static const empty = OrdersListFilters();
}
