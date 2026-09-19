import 'package:flutter/services.dart';

import '../../features/pos/domain/pos_models.dart';

class PrinterService {
  static const MethodChannel _channel = MethodChannel(
    'top_coffee_pos/printer',
  );

  Future<void> connect(String ipAddress) async {
    await _channel.invokeMethod<bool>(
      'connect',
      <String, dynamic>{
        'ip': ipAddress,
      },
    );
  }

  Future<void> printTest() async {
    await _channel.invokeMethod<bool>('printTest');
  }

  Future<void> printReceipt(OrderReceipt receipt) async {
    final payments = receipt.payments.isNotEmpty
        ? receipt.payments
        : receipt.payment != null
            ? <PaymentConfirmation>[receipt.payment!]
            : <PaymentConfirmation>[];

    final paymentMethod = payments.length > 1
        ? 'Split'
        : payments.isNotEmpty
            ? payments.first.method
            : '';

    final tendered = payments.length == 1 &&
            payments.first.tendered != null
        ? payments.first.tendered!.toStringAsFixed(2)
        : null;

    final changeDue = payments.length == 1 &&
            payments.first.changeDue != null
        ? payments.first.changeDue!.toStringAsFixed(2)
        : null;

    final items = receipt.items.map((item) {
      final itemName = item.variantName?.isNotEmpty == true
          ? '${item.productName} - ${item.variantName}'
          : item.productName;

      return <String, dynamic>{
        'name': itemName,
        'quantity': item.quantity,
        'lineTotal': item.lineTotal.toStringAsFixed(2),
      };
    }).toList();

    await _channel.invokeMethod<bool>(
      'printReceipt',
      <String, dynamic>{
        'orderNumber': receipt.orderId.toString(),
        'branchName': receipt.branchName ?? 'TOP COFFEE',
        'cashierName': receipt.cashierName ?? '',
        'tableName': receipt.tableName ?? '',
        'orderType': receipt.orderType,
        'subtotal': receipt.subtotal.toStringAsFixed(2),
        'discount': receipt.discountTotal.toStringAsFixed(2),
        'total': receipt.total.toStringAsFixed(2),
        'paymentMethod': paymentMethod,
        'tendered': tendered,
        'changeDue': changeDue,
        'items': items,
      },
    );
  }
  Future<void> disconnect() async {
    await _channel.invokeMethod<bool>('disconnect');
  }
}