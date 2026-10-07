import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../receipt/customer_bill.dart';
import '../../features/pos/domain/pos_models.dart';
import '../../features/settings/data/receipt_settings.dart';

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

  Future<void> printKhmerTest() async {
    await _channel.invokeMethod<bool>('printKhmerTest');
  }
  Future<void> printBitmapStressTest() async {
    await _channel.invokeMethod<bool>('printBitmapStressTest');
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/receipt_logo.png');

    if (!await file.exists()) {
      return null;
    }

    return file.readAsBytes();
  }

  Future<void> printReceipt(OrderReceipt receipt) async {
    final settings = await ReceiptSettings.load();
    final logoBytes = await _loadLogoBytes();

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
            payments.first.tendered != null &&
            settings.showTendered
        ? payments.first.tendered!.toStringAsFixed(2)
        : null;

    final changeDue = payments.length == 1 &&
            payments.first.changeDue != null &&
            settings.showChange
        ? payments.first.changeDue!.toStringAsFixed(2)
        : null;

    final items = receipt.items.map((item) {
      final itemName = item.variantName?.isNotEmpty == true
          ? '${item.productName} - ${item.variantName}'
          : item.productName;

      return <String, dynamic>{
        'name': settings.showItemName ? itemName : '',
        'quantity': settings.showQuantity ? item.quantity : '',
        'unitPrice': settings.showUnitPrice
            ? item.unitPrice.toStringAsFixed(2)
            : '',
        'lineTotal': settings.showLineTotal
            ? item.lineTotal.toStringAsFixed(2)
            : '',
      };
    }).toList();

    await _channel.invokeMethod<bool>(
      'printReceipt',
      <String, dynamic>{
        'logoBytes': logoBytes,
        'logoPosition': settings.logoPosition,
        'logoSize': settings.logoSize,
        'bodyFontSize': settings.bodyFontSize,
        'businessFontSize': settings.businessFontSize,
        'footerFontSize': settings.footerFontSize,
        'boldBusinessName': settings.boldBusinessName,
        'boldTotal': settings.boldTotal,
        'boldFooter': settings.boldFooter,
        'documentTitle': '',
        'orderNumber': settings.showOrderNumber
            ? receipt.displayOrderReference
            : '',
        'businessName': settings.businessName,
        'branchName': receipt.branchName?.trim().isNotEmpty == true
            ? receipt.branchName!.trim()
            : settings.branchName,
        'cashierName':
            settings.showCashier ? receipt.cashierName ?? '' : '',
        'tableName':
            settings.showTable ? receipt.tableName ?? '' : '',
        'orderType':
            settings.showOrderType ? receipt.orderType : '',
        'subtotal': receipt.subtotal.toStringAsFixed(2),
        'discount': receipt.discountTotal.toStringAsFixed(2),
        'total': receipt.total.toStringAsFixed(2),
        'paymentMethod':
            settings.showPaymentMethod ? paymentMethod : '',
        'tendered': tendered,
        'changeDue': changeDue,
        'showSplitPayments': settings.showSplitPayments,
        'payments': payments
            .map(
              (payment) => <String, dynamic>{
                'method': payment.method,
                'amount': payment.amount.toStringAsFixed(2),
              },
            )
            .toList(),
        'footer': settings.footer,
        'items': items,
      },
    );
  }
  Future<void> printBill(CustomerBill bill) async {
    final settings = await ReceiptSettings.load();
    final logoBytes = await _loadLogoBytes();

    final items = bill.items.map((item) {
      return <String, dynamic>{
        'name': settings.showItemName ? item.displayName : '',
        'quantity': settings.showQuantity ? item.quantity : '',
        'unitPrice': settings.showUnitPrice
            ? item.unitPrice.toStringAsFixed(2)
            : '',
        'lineTotal': settings.showLineTotal
            ? item.lineTotal.toStringAsFixed(2)
            : '',
      };
    }).toList();

    await _channel.invokeMethod<bool>(
      'printReceipt',
      <String, dynamic>{
        'logoBytes': logoBytes,
        'logoPosition': settings.logoPosition,
        'logoSize': settings.logoSize,
        'bodyFontSize': settings.bodyFontSize,
        'businessFontSize': settings.businessFontSize,
        'footerFontSize': settings.footerFontSize,
        'boldBusinessName': settings.boldBusinessName,
        'boldTotal': settings.boldTotal,
        'boldFooter': settings.boldFooter,
        'documentTitle': 'BILL · UNPAID',
        'orderNumber': settings.showOrderNumber ? bill.displayReference : '',
        'businessName': settings.businessName,
        'branchName': bill.branchName?.trim().isNotEmpty == true
            ? bill.branchName!.trim()
            : settings.branchName,
        'cashierName': settings.showCashier ? bill.cashierName ?? '' : '',
        'tableName': settings.showTable ? bill.tableName ?? '' : '',
        'orderType': settings.showOrderType ? bill.orderType : '',
        'subtotal': bill.subtotal.toStringAsFixed(2),
        'discount': bill.discountTotal.toStringAsFixed(2),
        'total': bill.total.toStringAsFixed(2),
        'paymentMethod': '',
        'tendered': null,
        'changeDue': null,
        'showSplitPayments': false,
        'payments': const <Map<String, dynamic>>[],
        'footer': settings.footer,
        'items': items,
      },
    );
  }

  Future<void> printReceiptBitmapTest(OrderReceipt receipt) async {
    final settings = await ReceiptSettings.load();

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
            payments.first.tendered != null &&
            settings.showTendered
        ? payments.first.tendered!.toStringAsFixed(2)
        : null;

    final changeDue = payments.length == 1 &&
            payments.first.changeDue != null &&
            settings.showChange
        ? payments.first.changeDue!.toStringAsFixed(2)
        : null;

    final items = receipt.items.map((item) {
      return <String, dynamic>{
        'name': settings.showItemName ? item.productName : '',
        'variant': settings.showItemName
            ? item.variantName ?? ''
            : '',
        'quantity': settings.showQuantity ? item.quantity : '',
        'unitPrice': settings.showUnitPrice
            ? item.unitPrice.toStringAsFixed(2)
            : '',
        'lineTotal': settings.showLineTotal
            ? item.lineTotal.toStringAsFixed(2)
            : '',
      };
    }).toList();

    await _channel.invokeMethod<bool>(
      'printReceiptBitmapTest',
      <String, dynamic>{
        'logoBytes': null,
        'logoPosition': settings.logoPosition,
        'logoSize': settings.logoSize,
        'bodyFontSize': settings.bodyFontSize,
        'businessFontSize': settings.businessFontSize,
        'footerFontSize': settings.footerFontSize,
        'boldBusinessName': settings.boldBusinessName,
        'boldTotal': settings.boldTotal,
        'boldFooter': settings.boldFooter,
        'orderNumber': settings.showOrderNumber
            ? receipt.displayOrderReference
            : '',
        'businessName': settings.businessName,
        'branchName': receipt.branchName?.trim().isNotEmpty == true
            ? receipt.branchName!.trim()
            : settings.branchName,
        'cashierName':
            settings.showCashier ? receipt.cashierName ?? '' : '',
        'tableName':
            settings.showTable ? receipt.tableName ?? '' : '',
        'orderType':
            settings.showOrderType ? receipt.orderType : '',
        'subtotal': receipt.subtotal.toStringAsFixed(2),
        'discount': receipt.discountTotal.toStringAsFixed(2),
        'total': receipt.total.toStringAsFixed(2),
        'paymentMethod':
            settings.showPaymentMethod ? paymentMethod : '',
        'tendered': tendered,
        'changeDue': changeDue,
        'showSplitPayments': settings.showSplitPayments,
        'payments': payments
            .map(
              (payment) => <String, dynamic>{
                'method': payment.method,
                'amount': payment.amount.toStringAsFixed(2),
              },
            )
            .toList(),
        'footer': settings.footer,
        'items': items,
      },
    );
  }
  Future<void> disconnect() async {
    await _channel.invokeMethod<bool>('disconnect');
  }
}
