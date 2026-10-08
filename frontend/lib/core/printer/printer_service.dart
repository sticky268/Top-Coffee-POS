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

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    try {
      final accepted = await _channel.invokeMethod<bool>(method, arguments);
      if (accepted != true) {
        throw PlatformException(
            code: 'printer_rejected',
            message:
                'The printer did not accept the job. Check its connection before retrying.');
      }
    } on MissingPluginException {
      throw StateError(
          'Receipt printing is unavailable on this device. Use an E-Receipt.');
    }
  }

  Future<void> connect(String ipAddress) async {
    await _invoke(
      'connect',
      <String, dynamic>{
        'ip': ipAddress,
      },
    );
  }

  Future<void> printTest() async {
    await _invoke('printTest');
  }

  Future<void> printKhmerTest() async {
    await _invoke('printKhmerTest');
  }

  Future<void> printBitmapStressTest() async {
    await _invoke('printBitmapStressTest');
  }

  String _logoFileName(String? branchKey) {
    final scope = branchKey?.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_-]+'),
          '_',
        );
    return scope == null || scope.isEmpty
        ? 'receipt_logo.png'
        : 'receipt_logo_$scope.png';
  }

  Future<Uint8List?> _loadLogoBytes(String? branchKey) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_logoFileName(branchKey)}');

    if (!await file.exists()) {
      return null;
    }

    return file.readAsBytes();
  }

  Future<void> printReceipt(OrderReceipt receipt) async {
    final settings = await ReceiptSettings.load(
      branchKey: receipt.branchCode,
      branchNameFallback: receipt.branchName,
    );
    final logoBytes = await _loadLogoBytes(receipt.branchCode);

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
        'unitPrice':
            settings.showUnitPrice ? item.unitPrice.toStringAsFixed(2) : '',
        'lineTotal':
            settings.showLineTotal ? item.lineTotal.toStringAsFixed(2) : '',
      };
    }).toList();

    await _invoke(
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
        'orderNumber':
            settings.showOrderNumber ? receipt.displayOrderReference : '',
        'businessName': settings.businessName,
        'branchName': settings.branchName,
        'cashierName': settings.showCashier ? receipt.cashierName ?? '' : '',
        'tableName': settings.showTable ? receipt.tableName ?? '' : '',
        'orderType': settings.showOrderType ? receipt.orderType : '',
        'subtotal': receipt.subtotal.toStringAsFixed(2),
        'discount': receipt.discountTotal.toStringAsFixed(2),
        'total': receipt.total.toStringAsFixed(2),
        'paymentMethod': settings.showPaymentMethod ? paymentMethod : '',
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
    final settings = await ReceiptSettings.load(
      branchKey: bill.branchCode,
      branchNameFallback: bill.branchName,
    );
    final logoBytes = await _loadLogoBytes(bill.branchCode);

    final items = bill.items.map((item) {
      return <String, dynamic>{
        'name': settings.showItemName ? item.displayName : '',
        'quantity': settings.showQuantity ? item.quantity : '',
        'unitPrice':
            settings.showUnitPrice ? item.unitPrice.toStringAsFixed(2) : '',
        'lineTotal':
            settings.showLineTotal ? item.lineTotal.toStringAsFixed(2) : '',
      };
    }).toList();

    await _invoke(
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
        'orderNumber': settings.showOrderNumber ? bill.displayReference : '',
        'businessName': settings.businessName,
        'branchName': settings.branchName,
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
    final settings = await ReceiptSettings.load(
      branchKey: receipt.branchCode,
      branchNameFallback: receipt.branchName,
    );

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
        'variant': settings.showItemName ? item.variantName ?? '' : '',
        'quantity': settings.showQuantity ? item.quantity : '',
        'unitPrice':
            settings.showUnitPrice ? item.unitPrice.toStringAsFixed(2) : '',
        'lineTotal':
            settings.showLineTotal ? item.lineTotal.toStringAsFixed(2) : '',
      };
    }).toList();

    await _invoke(
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
        'orderNumber':
            settings.showOrderNumber ? receipt.displayOrderReference : '',
        'businessName': settings.businessName,
        'branchName': settings.branchName,
        'cashierName': settings.showCashier ? receipt.cashierName ?? '' : '',
        'tableName': settings.showTable ? receipt.tableName ?? '' : '',
        'orderType': settings.showOrderType ? receipt.orderType : '',
        'subtotal': receipt.subtotal.toStringAsFixed(2),
        'discount': receipt.discountTotal.toStringAsFixed(2),
        'total': receipt.total.toStringAsFixed(2),
        'paymentMethod': settings.showPaymentMethod ? paymentMethod : '',
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
    await _invoke('disconnect');
  }
}
