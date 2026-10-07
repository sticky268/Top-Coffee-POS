import '../../features/pos/domain/pos_models.dart';

class CustomerBillLine {
  const CustomerBillLine({
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final String? variantName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  String get displayName {
    final variant = variantName?.trim();
    return variant != null && variant.isNotEmpty
        ? '$productName · $variant'
        : productName;
  }
}

class CustomerBill {
  const CustomerBill({
    this.orderReference,
    required this.orderType,
    this.branchName,
    this.cashierName,
    this.tableName,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.items,
    this.createdAt,
  });

  final String? orderReference;
  final String orderType;
  final String? branchName;
  final String? cashierName;
  final String? tableName;
  final double subtotal;
  final double discountTotal;
  final double total;
  final List<CustomerBillLine> items;
  final DateTime? createdAt;

  bool get isDraft => orderReference?.trim().isEmpty ?? true;

  String get displayReference =>
      isDraft ? 'Draft' : orderReference!.trim();

  factory CustomerBill.fromReceipt(OrderReceipt receipt) {
    return CustomerBill(
      orderReference: receipt.displayOrderReference,
      orderType: receipt.orderType,
      branchName: receipt.branchName,
      cashierName: receipt.cashierName,
      tableName: receipt.tableName,
      subtotal: receipt.subtotal,
      discountTotal: receipt.discountTotal,
      total: receipt.total,
      items: receipt.items
          .map(
            (item) => CustomerBillLine(
              productName: item.productName,
              variantName: item.variantName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      createdAt: receipt.createdAt,
    );
  }
}
