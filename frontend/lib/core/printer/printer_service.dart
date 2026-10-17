import 'dart:io';

import 'ios_network_printer.dart';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../receipt/customer_bill.dart';
import '../../features/pos/domain/pos_models.dart';
import '../../features/settings/data/receipt_settings.dart';

class PrinterService {
  static const MethodChannel _channel = MethodChannel('top_coffee_pos/printer');

  static final IosNetworkPrinter _iosPrinter = IosNetworkPrinter();

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (Platform.isIOS) {
      await _iosPrinter.invoke(method, arguments);
      return;
    }
    try {
      final accepted = await _channel.invokeMethod<bool>(method, arguments);
      if (accepted != true) {
        throw PlatformException(
          code: 'printer_rejected',
          message:
              'The printer did not accept the job. Check its connection before retrying.',
        );
      }
    } on MissingPluginException {
      throw StateError(
        method == 'openCashDrawer'
            ? 'Cash drawer control is unavailable on this device.'
            : 'Receipt printing is unavailable on this device. Use an E-Receipt.',
      );
    }
  }

  Future<void> connect(String ipAddress) async {
    await _invoke('connect', <String, dynamic>{'ip': ipAddress});
  }

  /// Sends a pulse only. The printer cannot confirm the physical drawer opened.
  Future<void> openCashDrawer() => _invoke('openCashDrawer');

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
    await sendPayload(await prepareReceipt(receipt));
  }

  Future<void> sendPayload(Map<String, dynamic> payload) =>
      _invoke('printReceipt', payload);

  Future<Map<String, dynamic>> prepareReceipt(OrderReceipt receipt) async {
    final settings = await ReceiptSettings.load(
      branchKey: receipt.branchCode,
      branchNameFallback: receipt.branchName,
    );
    return prepareReceiptWithSettings(receipt, settings);
  }

  Future<Map<String, dynamic>> prepareReceiptWithSettings(
    OrderReceipt receipt,
    ReceiptSettings settings,
  ) async {
    final logoBytes =
        settings.showLogo ? await _loadLogoBytes(receipt.branchCode) : null;

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

    return <String, dynamic>{
      'fontStyle': settings.fontStyle,
      'showLogo': settings.showLogo,
      'showItemName': settings.showItemName,
      'showQuantity': settings.showQuantity,
      'showUnitPrice': settings.showUnitPrice,
      'showLineTotal': settings.showLineTotal,
      'dateTime': settings.showDateTime && receipt.createdAt != null
          ? DateFormat('dd/MM/yyyy h:mm a').format(receipt.createdAt!.toLocal())
          : '',
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
      'businessName': settings.businessName.trim().isEmpty
          ? ReceiptSettings.defaultBusinessName
          : settings.businessName.trim(),
      'branchName': settings.branchName,
      'cashierName': settings.showCashier ? receipt.cashierName ?? '' : '',
      'tableName': settings.showTable ? receipt.tableName ?? '' : '',
      'orderType': settings.showOrderType ? receipt.orderType : '',
      'subtotal': receipt.subtotal.toStringAsFixed(2),
      'discount': receipt.discountTotal.toStringAsFixed(2),
      'total': receipt.total.toStringAsFixed(2),
      'supplemental': receipt.supplementalTotal.toStringAsFixed(2),
      'refunded': receipt.refundedTotal.toStringAsFixed(2),
      'netPaid': receipt.netPaid.toStringAsFixed(2),
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
    };
  }

  Future<void> printBill(CustomerBill bill) async {
    await sendPayload(await prepareBill(bill));
  }

  Future<Map<String, dynamic>> prepareBill(CustomerBill bill) async {
    final settings = await ReceiptSettings.load(
      branchKey: bill.branchCode,
      branchNameFallback: bill.branchName,
    );
    return prepareBillWithSettings(bill, settings);
  }

  Future<Map<String, dynamic>> prepareBillWithSettings(
    CustomerBill bill,
    ReceiptSettings settings,
  ) async {
    final logoBytes =
        settings.showLogo ? await _loadLogoBytes(bill.branchCode) : null;

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

    return <String, dynamic>{
      'fontStyle': settings.fontStyle,
      'showLogo': settings.showLogo,
      'showItemName': settings.showItemName,
      'showQuantity': settings.showQuantity,
      'showUnitPrice': settings.showUnitPrice,
      'showLineTotal': settings.showLineTotal,
      'dateTime': settings.showDateTime && bill.createdAt != null
          ? DateFormat('dd/MM/yyyy h:mm a').format(bill.createdAt!.toLocal())
          : '',
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
      'businessName': settings.businessName.trim().isEmpty
          ? ReceiptSettings.defaultBusinessName
          : settings.businessName.trim(),
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
    };
  }

  Future<void> printReceiptBitmapTest(OrderReceipt receipt) async {
    if (Platform.isIOS) {
      await sendPayload(await prepareReceipt(receipt));
      return;
    }
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

    await _invoke('printReceiptBitmapTest', <String, dynamic>{
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
      'businessName': settings.businessName.trim().isEmpty
          ? ReceiptSettings.defaultBusinessName
          : settings.businessName.trim(),
      'branchName': settings.branchName,
      'cashierName': settings.showCashier ? receipt.cashierName ?? '' : '',
      'tableName': settings.showTable ? receipt.tableName ?? '' : '',
      'orderType': settings.showOrderType ? receipt.orderType : '',
      'subtotal': receipt.subtotal.toStringAsFixed(2),
      'discount': receipt.discountTotal.toStringAsFixed(2),
      'total': receipt.total.toStringAsFixed(2),
      'supplemental': receipt.supplementalTotal.toStringAsFixed(2),
      'refunded': receipt.refundedTotal.toStringAsFixed(2),
      'netPaid': receipt.netPaid.toStringAsFixed(2),
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
    });
  }

  Future<void> disconnect() async {
    await _invoke('disconnect');
  }
}
