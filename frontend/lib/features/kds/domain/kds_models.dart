import 'package:flutter/foundation.dart';

@immutable
class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.order,
    required this.status,
    this.sentAt,
    this.readyAt,
    this.completedAt,
    this.cancellationReason,
  });

  final int id;
  final KitchenOrder order;
  final String status;
  final DateTime? sentAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final String? cancellationReason;

  factory KitchenTicket.fromJson(Map<String, dynamic> json) {
    return KitchenTicket(
      id: json['id'] as int,
      order: KitchenOrder.fromJson(
        json['order'] as Map<String, dynamic>,
      ),
      status: json['status'] as String,
      sentAt: _parseDate(json['sent_at']),
      readyAt: _parseDate(json['ready_at']),
      completedAt: _parseDate(json['completed_at']),
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }

  KitchenTicket copyWith({
    String? status,
    DateTime? sentAt,
    DateTime? readyAt,
    DateTime? completedAt,
    String? cancellationReason,
  }) {
    return KitchenTicket(
      id: id,
      order: order,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      readyAt: readyAt ?? this.readyAt,
      completedAt: completedAt ?? this.completedAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

@immutable
class KitchenOrder {
  const KitchenOrder({
    required this.id,
    required this.orderType,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.items,
    this.table,
  });

  final int id;
  final String orderType;
  final String status;
  final double total;
  final DateTime createdAt;
  final List<KitchenOrderItem> items;
  final KitchenTable? table;

  factory KitchenOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];

    return KitchenOrder(
      id: json['id'] as int,
      orderType: json['order_type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      total: _toDouble(json['total']),
      createdAt: DateTime.parse(json['created_at'].toString()),
      items: rawItems
          .map(
            (item) => KitchenOrderItem.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      table: json['table'] == null
          ? null
          : KitchenTable.fromJson(
              json['table'] as Map<String, dynamic>,
            ),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class KitchenOrderItem {
  const KitchenOrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.variantName,
    this.notes,
  });

  final int id;
  final String productName;
  final double quantity;
  final double unitPrice;
  final String? variantName;
  final String? notes;

  factory KitchenOrderItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final variant = json['variant'] as Map<String, dynamic>?;

    return KitchenOrderItem(
      id: json['id'] as int,
      productName: product?['name'] as String? ?? 'Unknown item',
      quantity: _toDouble(json['quantity']),
      unitPrice: _toDouble(json['unit_price']),
      variantName: variant?['name'] as String?,
      notes: json['notes'] as String?,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class KitchenTable {
  const KitchenTable({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory KitchenTable.fromJson(Map<String, dynamic> json) {
    return KitchenTable(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }
}
