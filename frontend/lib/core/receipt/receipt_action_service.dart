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
    final settings = await ReceiptSettings.load();

    if (!settings.printerEnabled) {
      throw StateError('Receipt printing is disabled in Settings.');
    }

    final printerIp = settings.printerIpAddress.trim();
    if (printerIp.isEmpty) {
      throw StateError('Printer IP address is not configured.');
    }

    final receipt = await loadReceipt(orderId);
    var connected = false;

    try {
      await _printerService.connect(printerIp);
      connected = true;
      await _printerService.printReceipt(receipt);
      return receipt;
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

  Future<OrderReceipt> shareElectronicReceipt(
    int orderId, {
    Rect? sharePositionOrigin,
  }) async {
    final receipt = await loadReceipt(orderId);
    final settings = await ReceiptSettings.load();
    final bytes = await _buildPdf(receipt, settings);

    final directory = await getTemporaryDirectory();
    final safeReference = receipt.displayOrderReference.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '-',
    );
    final file = File(
      '${directory.path}/top-coffee-receipt-$safeReference.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'application/pdf'),
        ],
        title: 'Top Coffee E-Receipt',
        subject: 'Receipt ${receipt.displayOrderReference}',
        text: 'Top Coffee receipt ${receipt.displayOrderReference}',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return receipt;
  }

  Future<List<int>> _buildPdf(
    OrderReceipt receipt,
    ReceiptSettings settings,
  ) async {
    final fontData = await rootBundle.load('assets/fonts/Inter.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document();

    final payments = receipt.payments.isNotEmpty
        ? receipt.payments
        : receipt.payment != null
            ? <PaymentConfirmation>[receipt.payment!]
            : <PaymentConfirmation>[];

    final branchName = (receipt.branchName?.trim().isNotEmpty ?? false)
        ? receipt.branchName!.trim()
        : settings.branchName.trim();
    final createdAt = receipt.createdAt != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(receipt.createdAt!.toLocal())
        : '';
    final orderType = receipt.orderType == 'dine_in'
        ? 'Dine-in'
        : receipt.orderType == 'takeaway'
            ? 'Takeaway'
            : receipt.orderType;
    final money = NumberFormat.currency(symbol: r'$');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
        ),
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
                if (branchName.isNotEmpty) ...<pw.Widget>[
                  pw.SizedBox(height: 4),
                  pw.Text(branchName, style: const pw.TextStyle(fontSize: 10)),
                ],
                pw.SizedBox(height: 14),
                pw.Text(
                  'E-RECEIPT',
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
                _pdfInfoRow('Order', receipt.displayOrderReference),
                if (settings.showDateTime && createdAt.isNotEmpty)
                  _pdfInfoRow('Date', createdAt),
                if (settings.showOrderType)
                  _pdfInfoRow('Type', orderType),
                if (settings.showTable &&
                    (receipt.tableName?.trim().isNotEmpty ?? false))
                  _pdfInfoRow('Table', receipt.tableName!.trim()),
                if (settings.showCashier &&
                    (receipt.cashierName?.trim().isNotEmpty ?? false))
                  _pdfInfoRow('Cashier', receipt.cashierName!.trim()),
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
          ...receipt.items.map((item) {
            final name = item.variantName?.trim().isNotEmpty == true
                ? '${item.productName} · ${item.variantName}'
                : item.productName;
            return pw.Container(
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
                          name,
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
            );
          }),
          pw.SizedBox(height: 16),
          _pdfAmountRow('Subtotal', money.format(receipt.subtotal)),
          if (receipt.discountTotal > 0)
            _pdfAmountRow(
              'Discount',
              '- ${money.format(receipt.discountTotal)}',
            ),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          _pdfAmountRow(
            'TOTAL',
            money.format(receipt.total),
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
            ...payments.map((payment) {
              final method = _paymentLabel(payment.method);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  children: <pw.Widget>[
                    _pdfInfoRow(
                      method,
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
              );
            }),
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
}

final receiptActionServiceProvider = Provider<ReceiptActionService>((ref) {
  return ReceiptActionService(ref.watch(posRepositoryProvider));
});
