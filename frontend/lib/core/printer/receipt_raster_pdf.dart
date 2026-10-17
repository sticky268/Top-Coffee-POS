import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_raster.dart';

/// A scrollable 80 mm E-Receipt, using the same shaped text and settings as paper.
Future<List<int>> receiptRasterPdf(Map<String, dynamic> payload) async {
  final image = await renderReceiptImage(payload);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not render the E-Receipt.');
    const width = 80 * PdfPageFormat.mm;
    const margin = 8.0;
    const contentWidth = width - margin * 2;
    final contentHeight = image.height * contentWidth / image.width;
    final document = pw.Document();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat(width, contentHeight + margin * 2),
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Image(
          pw.MemoryImage(bytes.buffer
              .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)),
          width: contentWidth,
          height: contentHeight),
    ));
    return document.save();
  } finally {
    image.dispose();
  }
}
