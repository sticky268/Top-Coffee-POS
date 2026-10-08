/// Domain models for order history. Framework-agnostic (no Flutter
/// imports) â€” same convention as auth/dashboard/pos domain files.
library;

class OrderBranchRef {
  const OrderBranchRef({required this.id, required this.name, required this.code});

  final int id;
  final String name;
  final String code;

  factory OrderBranchRef.fromJson(Map<String, dynamic> json) {
    return OrderBranchRef(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
    );
  }
}

class OrderCashierRef {
  const OrderCashierRef({required this.id, required this.name});

  final int id;
  final String name;

  factory OrderCashierRef.fromJson(Map<String, dynamic> json) {
    return OrderCashierRef(id: json['id'] as int, name: json['name'] as String);
  }
}

/// Lightweight payment info shown on list rows â€” see [OrderPaymentDetail]
/// for the fuller version shown on the detail screen.
class OrderPaymentSummary {
  const OrderPaymentSummary({required this.method, required this.status});

  final String method;
  final String status;

  factory OrderPaymentSummary.fromJson(Map<String, dynamic> json) {
    return OrderPaymentSummary(method: json['method'] as String, status: json['status'] as String);
  }
}

class OrderPaymentDetail {
  const OrderPaymentDetail({
    this.id,
    required this.method,
    required this.status,
    required this.amount,
    this.tendered,
    this.changeDue,
    this.refundedAmount = 0,
    this.refundableAmount = 0,
  });

  final int? id;
  final String method;
  final String status;
  final double amount;
  final double? tendered;
  final double? changeDue;
  final double refundedAmount;
  final double refundableAmount;

  factory OrderPaymentDetail.fromJson(Map<String, dynamic> json) {
    return OrderPaymentDetail(
      id: json['id'] != null ? (json['id'] as num).toInt() : null,
      method: json['method'] as String,
      status: json['status'] as String,
      amount: (json['amount'] as num).toDouble(),
      tendered: json['tendered'] != null
          ? (json['tendered'] as num).toDouble()
          : null,
      changeDue: json['change_due'] != null
          ? (json['change_due'] as num).toDouble()
          : null,
      refundedAmount: json['refunded_amount'] != null
          ? (json['refunded_amount'] as num).toDouble()
          : 0,
      refundableAmount: json['refundable_amount'] != null
          ? (json['refundable_amount'] as num).toDouble()
          : 0,
    );
  }
}

class OrderLineItem {
  const OrderLineItem({
    required this.id,
    required this.productId,
    this.productVariantId,
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int id;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    return OrderLineItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productVariantId: json['product_variant_id'] as int?,
      productName: json['product_name'] as String,
      variantName: json['variant_name'] as String?,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      lineTotal: (json['line_total'] as num).toDouble(),
    );
  }
}

/// One row in the order list â€” matches GET /api/v1/orders's per-item shape
/// (no line items â€” that's [OrderDetail]'s job).
class OrderSummary {
  const OrderSummary({
    required this.id,
    this.orderNumber,
    required this.uuid,
    required this.orderType,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.branch,
    required this.cashier,
    required this.payment,
    required this.createdAt,
  });

  final int id;
  final int? orderNumber;
  final String uuid;
  final String orderType;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double total;

  // Nullable throughout: a historical order's branch/cashier/payment
  // could theoretically be missing (soft-deleted user, data anomaly) â€”
  // the UI must never assume these are present.
  final OrderBranchRef? branch;
  final OrderCashierRef? cashier;
  final OrderPaymentSummary? payment;
  final DateTime? createdAt;

  int get effectiveOrderNumber => orderNumber ?? id;

  String get displayOrderNumber =>
      effectiveOrderNumber.toString().padLeft(6, '0');

  String get displayOrderReference {
    final code = branch?.code.trim();
    return code != null && code.isNotEmpty
        ? '$code-$displayOrderNumber'
        : displayOrderNumber;
  }

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      id: json['id'] as int,
      orderNumber: (json['order_number'] as num?)?.toInt(),
      uuid: json['uuid'] as String,
      orderType: json['order_type'] as String,
      status: json['status'] as String,
      subtotal: (json['subtotal'] as num).toDouble(),
      discountTotal: (json['discount_total'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      branch: json['branch'] != null ? OrderBranchRef.fromJson(json['branch'] as Map<String, dynamic>) : null,
      cashier: json['cashier'] != null ? OrderCashierRef.fromJson(json['cashier'] as Map<String, dynamic>) : null,
      payment:
          json['payment'] != null ? OrderPaymentSummary.fromJson(json['payment'] as Map<String, dynamic>) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }
}

/// Table reference included with a dine-in order detail.
class OrderTableRef {
  const OrderTableRef({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
  });

  final int id;
  final String name;
  final int capacity;
  final String status;

  factory OrderTableRef.fromJson(Map<String, dynamic> json) {
    return OrderTableRef(
      id: json['id'] as int,
      name: json['name'] as String,
      capacity: json['capacity'] as int,
      status: json['status'] as String,
    );
  }
}

/// Full order detail â€” matches GET /api/v1/orders/{id}.
class OrderDetail {
  const OrderDetail({
    required this.id,
    this.orderNumber,
    required this.uuid,
    required this.orderType,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.branch,
    required this.cashier,
    this.table,
    required this.items,
    required this.payment,
    this.payments = const [],
    required this.createdAt,
  });

  final int id;
  final int? orderNumber;
  final String uuid;
  final String orderType;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double total;
  final OrderBranchRef? branch;
  final OrderCashierRef? cashier;
  final OrderTableRef? table;
  final List<OrderLineItem> items;
  final OrderPaymentDetail? payment;
  final List<OrderPaymentDetail> payments;
  final DateTime? createdAt;

  int get effectiveOrderNumber => orderNumber ?? id;

  String get displayOrderNumber =>
      effectiveOrderNumber.toString().padLeft(6, '0');

  String get displayOrderReference {
    final code = branch?.code.trim();
    return code != null && code.isNotEmpty
        ? '$code-$displayOrderNumber'
        : displayOrderNumber;
  }

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    return OrderDetail(
      id: json['id'] as int,
      orderNumber: (json['order_number'] as num?)?.toInt(),
      uuid: json['uuid'] as String,
      orderType: json['order_type'] as String,
      status: json['status'] as String,
      subtotal: (json['subtotal'] as num).toDouble(),
      discountTotal: (json['discount_total'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      branch: json['branch'] != null ? OrderBranchRef.fromJson(json['branch'] as Map<String, dynamic>) : null,
      cashier: json['cashier'] != null ? OrderCashierRef.fromJson(json['cashier'] as Map<String, dynamic>) : null,
      table: json['table'] != null ? OrderTableRef.fromJson(json['table'] as Map<String, dynamic>) : null,
      items: (json['items'] as List? ?? const [])
          .map((item) => OrderLineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      payment:
          json['payment'] != null ? OrderPaymentDetail.fromJson(json['payment'] as Map<String, dynamic>) : null,
      payments: (json['payments'] as List? ?? const [])
          .map(
            (payment) => OrderPaymentDetail.fromJson(
              payment as Map<String, dynamic>,
            ),
          )
          .toList(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }
}

/// One fetched page of the order list, from GET /api/v1/orders's `meta`
/// block â€” used internally by the repository/controller, not the raw
/// paginator itself.
class OrderListPage {
  const OrderListPage({
    required this.orders,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<OrderSummary> orders;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

