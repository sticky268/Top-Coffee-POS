import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../features/pos/data/pos_repository.dart';
import '../../features/pos/domain/pos_models.dart';
import '../../features/settings/data/receipt_settings.dart';
import '../printer/printer_service.dart';
import 'customer_bill.dart';

class ReceiptActionService {
  ReceiptActionService(
    this._repository, {
    PrinterService? printerService,
  }) : _printerService = printerService ?? PrinterService();

  final PosRepository _repository;
  final PrinterService _printerService;

  Future<OrderReceipt> loadReceipt(int orderId) {
    return _repository.getOrderReceipt(orderId: orderId);
  }

  Future<OrderReceipt> printReceipt(int orderId) async {
    final receipt = await loadReceipt(orderId);
    if (receipt.status != 'completed') {
      throw StateError('Only completed orders can print a receipt.');
    }

    await _withPrinter(
      branchKey: receipt.branchCode,
      branchNameFallback: receipt.branchName,
      action: (_) => _printerService.printReceipt(receipt),
    );
    return receipt;
  }

  Future<void> printBill(CustomerBill bill) async {
    await _withPrinter(
      branchKey: bill.branchCode,
      branchNameFallback: bill.branchName,
      action: (_) => _printerService.printBill(bill),
    );
  }

  Future<OrderReceipt> shareElectronicReceipt(
    int orderId, {
    Rect? sharePositionOrigin,
  }) async {
    final receipt = await loadReceipt(orderId);
    if (receipt.status != 'completed') {
      throw StateError('Only completed orders can issue an E-Receipt.');
    }

    final settings = await ReceiptSettings.load(
      branchKey: receipt.branchCode,
      branchNameFallback: receipt.branchName,
    );
    final bytes = await _buildReceiptPdf(receipt, settings);
    final reference = receipt.displayOrderReference;

    await _sharePdf(
      bytes: bytes,
      filePrefix: 'top-coffee-receipt',
      reference: reference,
      title: 'Top Coffee E-Receipt',
      subject: 'Receipt $reference',
      text: 'Top Coffee receipt $reference',
      sharePositionOrigin: sharePositionOrigin,
    );

    return receipt;
  }

  Future<void> shareElectronicBill(
    CustomerBill bill, {
    Rect? sharePositionOrigin,
  }) async {
    final settings = await ReceiptSettings.load(
      branchKey: bill.branchCode,
      branchNameFallback: bill.branchName,
    );
    final bytes = await _buildBillPdf(bill, settings);

    await _sharePdf(
      bytes: bytes,
      filePrefix: 'top-coffee-bill',
      reference: bill.displayReference,
      title: 'Top Coffee E-Bill',
      subject: 'Bill ${bill.displayReference}',
      text: 'Top Coffee unpaid bill ${bill.displayReference}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> _withPrinter({
    required String? branchKey,
    required String? branchNameFallback,
    required Future<void> Function(ReceiptSettings settings) action,
  }) async {
    final settings = await ReceiptSettings.load(
      branchKey: branchKey,
      branchNameFallback: branchNameFallback,
    );

    if (!settings.printerEnabled) {
      throw StateError('Printing is disabled in Settings.');
    }

    final printerIp = settings.printerIpAddress.trim();
    if (printerIp.isEmpty) {
      throw StateError('Printer IP address is not configured.');
    }

    var connected = false;
    try {
      await _printerService.connect(printerIp);
      connected = true;
      await action(settings);
    } finally {
      if (connected) {
        try {
          await _printerService.disconnect();
        } catch (_) {
          // A completed or failed print should not be masked by disconnect.
        }
      }
    }
  }

  Future<void> _sharePdf({
    required List<int> bytes,
    required String filePrefix,
    required String reference,
    required String title,
    required String subject,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    final directory = await getTemporaryDirectory();
    final safeReference = reference.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '-',
    );
    final file = File(
      '${directory.path}/$filePrefix-$safeReference.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'application/pdf'),
        ],
        title: title,
        subject: subject,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<List<int>> _buildReceiptPdf(
    OrderReceipt receipt,
    ReceiptSettings settings,
  ) async {
    final payments = receipt.payments.isNotEmpty
        ? receipt.payments
        : receipt.payment != null
            ? <PaymentConfirmation>[receipt.payment!]
            : <PaymentConfirmation>[];

    return _buildPdf(
      settings: settings,
      documentTitle: '',
      orderReference: receipt.displayOrderReference,
      orderType: receipt.orderType,
      branchName: receipt.branchName,
      cashierName: receipt.cashierName,
      tableName: receipt.tableName,
      subtotal: receipt.subtotal,
      discountTotal: receipt.discountTotal,
      total: receipt.total,
      createdAt: receipt.createdAt,
      items: receipt.items
          .map(
            (item) => _PdfLine(
              name: item.variantName?.trim().isNotEmpty == true
                  ? '${item.productName} · ${item.variantName}'
                  : item.productName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      payments: payments,
    );
  }

  Future<List<int>> _buildBillPdf(
    CustomerBill bill,
    ReceiptSettings settings,
  ) {
    return _buildPdf(
      settings: settings,
      documentTitle: 'E-BILL · UNPAID',
      orderReference: bill.displayReference,
      orderType: bill.orderType,
      branchName: bill.branchName,
      cashierName: bill.cashierName,
      tableName: bill.tableName,
      subtotal: bill.subtotal,
      discountTotal: bill.discountTotal,
      total: bill.total,
      createdAt: bill.createdAt ?? DateTime.now(),
      items: bill.items
          .map(
            (item) => _PdfLine(
              name: item.displayName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      payments: const <PaymentConfirmation>[],
    );
  }

  Future<List<int>> _buildPdf({
    required ReceiptSettings settings,
    required String documentTitle,
    required String orderReference,
    required String orderType,
    required String? branchName,
    required String? cashierName,
    required String? tableName,
    required double subtotal,
    required double discountTotal,
    required double total,
    required DateTime? createdAt,
    required List<_PdfLine> items,
    required List<PaymentConfirmation> payments,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Inter.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document();
    final resolvedBranchName = settings.branchName.trim();
    final createdAtText = createdAt != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(createdAt.toLocal())
        : '';
    final orderTypeText = _orderTypeLabel(orderType);
    final money = NumberFormat.currency(symbol: r'$');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (context) => <pw.Widget>[
          pw.Center(
            child: pw.Column(
              children: <pw.Widget>[
                pw.Text(
                  settings.businessName,
                  style: const pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (resolvedBranchName.isNotEmpty) ...<pw.Widget>[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    resolvedBranchName,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
                pw.SizedBox(height: 14),
                pw.Text(
                  documentTitle,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              children: <pw.Widget>[
                _pdfInfoRow('Order', orderReference),
                if (settings.showDateTime && createdAtText.isNotEmpty)
                  _pdfInfoRow('Date', createdAtText),
                if (settings.showOrderType)
                  _pdfInfoRow('Type', orderTypeText),
                if (settings.showTable &&
                    (tableName?.trim().isNotEmpty ?? false))
                  _pdfInfoRow('Table', tableName!.trim()),
                if (settings.showCashier &&
                    (cashierName?.trim().isNotEmpty ?? false))
                  _pdfInfoRow('Cashier', cashierName!.trim()),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'ITEMS',
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          pw.SizedBox(height: 8),
          ...items.map(
            (item) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          item.name,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${item.quantity} × ${money.format(item.unitPrice)}',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    money.format(item.lineTotal),
                    style: const pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          _pdfAmountRow('Subtotal', money.format(subtotal)),
          if (discountTotal > 0)
            _pdfAmountRow(
              'Discount',
              '- ${money.format(discountTotal)}',
            ),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          _pdfAmountRow(
            'TOTAL',
            money.format(total),
            emphasized: true,
          ),
          if (payments.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 18),
            pw.Text(
              'PAYMENT',
              style: const pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            pw.SizedBox(height: 8),
            ...payments.map(
              (payment) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  children: <pw.Widget>[
                    _pdfInfoRow(
                      _paymentLabel(payment.method),
                      money.format(payment.amount),
                    ),
                    if (settings.showTendered && payment.tendered != null)
                      _pdfInfoRow(
                        'Cash received',
                        money.format(payment.tendered),
                      ),
                    if (settings.showChange &&
                        payment.changeDue != null &&
                        payment.changeDue! > 0)
                      _pdfInfoRow(
                        'Change',
                        money.format(payment.changeDue),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (settings.footer.trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                settings.footer.trim(),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 86,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfAmountRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = pw.TextStyle(
      fontSize: emphasized ? 14 : 10,
      fontWeight: emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  static String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'qr':
        return 'QR';
      case 'split':
        return 'Split payment';
      default:
        return method;
    }
  }

  static String _orderTypeLabel(String orderType) {
    switch (orderType) {
      case 'dine_in':
        return 'Dine-in';
      case 'takeaway':
        return 'Takeaway';
      default:
        return orderType;
    }
  }
}

class _PdfLine {
  const _PdfLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
}

final receiptActionServiceProvider = Provider<ReceiptActionService>((ref) {
  return ReceiptActionService(ref.watch(posRepositoryProvider));
});
