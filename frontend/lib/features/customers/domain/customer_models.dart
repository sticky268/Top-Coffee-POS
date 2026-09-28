class Customer {
  const Customer({
    required this.id,
    required this.branchId,
    required this.name,
    required this.phone,
    required this.email,
    required this.notes,
    required this.completedOrdersCount,
    required this.completedOrdersTotal,
    this.orders = const [],
  });

  final int id;
  final int? branchId;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final int completedOrdersCount;
  final double completedOrdersTotal;
  final List<CustomerOrder> orders;

  factory Customer.fromJson(Map<String, dynamic> json) {
    final ordersJson = json['orders'];

    return Customer(
      id: json['id'] as int,
      branchId: json['branch_id'] as int?,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      completedOrdersCount:
          (json['completed_orders_count'] as num?)?.toInt() ?? 0,
      completedOrdersTotal:
          double.tryParse(
            json['completed_orders_total']?.toString() ?? '0',
          ) ??
          0,
      orders: ordersJson is List
          ? ordersJson
              .whereType<Map<String, dynamic>>()
              .map(CustomerOrder.fromJson)
              .toList()
          : const [],
    );
  }
}

class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.uuid,
    required this.branchId,
    required this.userId,
    required this.customerId,
    required this.tableId,
    required this.orderType,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.heldAt,
    required this.completedAt,
    required this.createdAt,
  });

  final int id;
  final String uuid;
  final int branchId;
  final int userId;
  final int? customerId;
  final int? tableId;
  final String orderType;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final DateTime? heldAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  factory CustomerOrder.fromJson(Map<String, dynamic> json) {
    return CustomerOrder(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      branchId: json['branch_id'] as int,
      userId: json['user_id'] as int,
      customerId: json['customer_id'] as int?,
      tableId: json['table_id'] as int?,
      orderType: json['order_type'] as String,
      status: json['status'] as String,
      subtotal: double.tryParse(
            json['subtotal']?.toString() ?? '0',
          ) ??
          0,
      discountTotal: double.tryParse(
            json['discount_total']?.toString() ?? '0',
          ) ??
          0,
      taxTotal: double.tryParse(
            json['tax_total']?.toString() ?? '0',
          ) ??
          0,
      total: double.tryParse(
            json['total']?.toString() ?? '0',
          ) ??
          0,
      heldAt: json['held_at'] != null
          ? DateTime.tryParse(json['held_at'].toString())
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class CustomerListPage {
  const CustomerListPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<Customer> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  factory CustomerListPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>;
    final meta = json['meta'] as Map<String, dynamic>;

    return CustomerListPage(
      data: data
          .map(
            (item) => Customer.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      perPage: meta['per_page'] as int,
      total: meta['total'] as int,
    );
  }
}

class CustomerOrderPage {
  const CustomerOrderPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<CustomerOrder> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  factory CustomerOrderPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>;
    final meta = json['meta'] as Map<String, dynamic>;

    return CustomerOrderPage(
      data: data
          .map(
            (item) => CustomerOrder.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      perPage: meta['per_page'] as int,
      total: meta['total'] as int,
    );
  }
}
