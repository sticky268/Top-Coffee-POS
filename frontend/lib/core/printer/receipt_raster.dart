import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

const receiptDotWidth = 576;
const receiptMargin = 24.0;
const receiptContentWidth = receiptDotWidth - receiptMargin * 2;

List<String> receiptFontFamilies(String style) => switch (style) {
      'Sans Serif' => const [
          'Helvetica',
          'Arial',
          'Inter',
          'TopCoffeeReceiptKhmer'
        ],
      'Serif' => const [
          'Times New Roman',
          'Times',
          'Inter',
          'TopCoffeeReceiptKhmer'
        ],
      'Monospace' => const [
          'Courier',
          'Courier New',
          'Menlo',
          'Inter',
          'TopCoffeeReceiptKhmer'
        ],
      _ => const ['Inter', 'TopCoffeeReceiptKhmer'],
    };

/// Fit into a size-specific square, so even very tall logos change size.
ui.Rect receiptLogoRect(
    ui.Rect source, String size, String position, double top) {
  final side = switch (size) { 'Small' => 96.0, 'Large' => 240.0, _ => 160.0 };
  final scale = side / math.max(source.width, source.height);
  final width = source.width * scale;
  final height = source.height * scale;
  final left = switch (position) {
    'Left' => receiptMargin,
    'Right' => receiptDotWidth - receiptMargin - width,
    _ => (receiptDotWidth - width) / 2,
  };
  return ui.Rect.fromLTWH(left, top, width, height);
}

/// Ignore empty white/transparent margins when sizing an uploaded logo.
ui.Rect receiptLogoInkBounds(ByteData pixels, int width, int height) {
  var left = width, right = -1, top = height, bottom = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (pixels.getUint8(offset + 3) > 32 &&
          (pixels.getUint8(offset) < 245 ||
              pixels.getUint8(offset + 1) < 245 ||
              pixels.getUint8(offset + 2) < 245)) {
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
  }
  return right < left
      ? ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble())
      : ui.Rect.fromLTRB(
          left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

Future<void>? _fontReady;

Future<void> _loadFont() => _fontReady ??= () async {
      final loader = FontLoader('TopCoffeeReceiptKhmer')
        ..addFont(rootBundle.load('assets/fonts/NotoSansKhmerUI-Regular.ttf'));
      await loader.load();
    }();

typedef ReceiptColumn = ({
  String key,
  String title,
  double width,
  ui.TextAlign align
});

/// Explicit flags are used for new jobs; older saved jobs infer visible columns.
List<ReceiptColumn> receiptColumns(Map<String, dynamic> payload) {
  final items = payload['items'] as List? ?? const [];
  bool visible(String key, String flag) =>
      payload[flag] as bool? ??
      items.any((item) => '${(item as Map)[key] ?? ''}'.isNotEmpty);
  final numeric = <ReceiptColumn>[
    if (visible('quantity', 'showQuantity'))
      (key: 'quantity', title: 'QTY', width: 64, align: ui.TextAlign.center),
    if (visible('unitPrice', 'showUnitPrice'))
      (key: 'unitPrice', title: 'PRICE', width: 104, align: ui.TextAlign.right),
    if (visible('lineTotal', 'showLineTotal'))
      (
        key: 'lineTotal',
        title: 'AMOUNT',
        width: 120,
        align: ui.TextAlign.right
      ),
  ];
  final showName = visible('name', 'showItemName');
  if (showName) {
    return [
      (
        key: 'name',
        title: 'ITEM',
        width: receiptContentWidth -
            numeric.fold<double>(0, (sum, c) => sum + c.width),
        align: ui.TextAlign.left
      ),
      ...numeric,
    ];
  }
  // Hidden names do not leave a large empty column.
  if (numeric.isEmpty) return [];
  final extra = (receiptContentWidth -
          numeric.fold<double>(0, (sum, c) => sum + c.width)) /
      numeric.length;
  return numeric
      .map((c) =>
          (key: c.key, title: c.title, width: c.width + extra, align: c.align))
      .toList();
}

/// This exact image drives both the iOS settings preview and ESC/POS output.
Future<ui.Image> renderReceiptImage(Map<String, dynamic> payload) async {
  await _loadFont();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  final paragraphs = <ui.Paragraph>[];
  ui.Picture? picture;
  ui.Image? logo;
  var y = 24.0;
  String value(String key) => payload[key]?.toString() ?? '';
  double size(String key, double small, double medium, double large) =>
      switch (value(key)) { 'Small' => small, 'Large' => large, _ => medium };
  final body = size('bodyFontSize', 22, 26, 30);
  final families = receiptFontFamilies(value('fontStyle'));
  ui.Paragraph text(String content, double width,
      {double? fontSize,
      bool bold = false,
      ui.TextAlign align = ui.TextAlign.left}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      fontSize: fontSize ?? body,
    ))
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xff000000),
        fontSize: fontSize ?? body,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        fontFamily: families.first,
        fontFamilyFallback: families.skip(1).toList(),
        fontVariations: [ui.FontVariation('wght', bold ? 700 : 400)],
      ))
      ..addText(content);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    paragraphs.add(paragraph);
    return paragraph;
  }

  void advance(double amount) {
    y += amount;
    if (y > 24000) throw StateError('Receipt is too long. Use an E-Receipt.');
  }

  void line(String content,
      {double? fontSize,
      bool bold = false,
      bool center = false,
      double gap = 6}) {
    if (content.trim().isEmpty) return;
    final p = text(content, receiptContentWidth,
        fontSize: fontSize,
        bold: bold,
        align: center ? ui.TextAlign.center : ui.TextAlign.left);
    canvas.drawParagraph(p, ui.Offset(receiptMargin, y));
    advance(p.height + gap);
  }

  void rule({bool heavy = false}) {
    advance(10);
    canvas.drawLine(
        ui.Offset(receiptMargin, y),
        ui.Offset(receiptDotWidth - receiptMargin, y),
        ui.Paint()
          ..color = const ui.Color(0xff000000)
          ..strokeWidth = heavy ? 2 : 1);
    advance(12);
  }

  void pair(String label, String amount,
      {bool bold = false, double? fontSize}) {
    final left =
        text(label, receiptContentWidth * .54, fontSize: fontSize, bold: bold);
    final right = text(amount, receiptContentWidth * .44,
        fontSize: fontSize, bold: bold, align: ui.TextAlign.right);
    canvas.drawParagraph(left, ui.Offset(receiptMargin, y));
    canvas.drawParagraph(
        right, ui.Offset(receiptMargin + receiptContentWidth * .56, y));
    advance(math.max(left.height, right.height) + 7);
  }

  String money(String amount) => amount.isEmpty ? '' : '\$$amount';
  void metadata(String key, String label) {
    if (value(key).isNotEmpty) line('$label${value(key)}');
  }

  try {
    final rawLogo = payload['logoBytes'];
    final bytes = rawLogo is Uint8List
        ? rawLogo
        : rawLogo is List
            ? Uint8List.fromList(rawLogo.cast<int>())
            : null;
    if (payload['showLogo'] != false && bytes != null && bytes.isNotEmpty) {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      try {
        logo = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      final pixels = await logo.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) throw StateError('Could not read the uploaded logo.');
      final source = receiptLogoInkBounds(pixels, logo.width, logo.height);
      final destination =
          receiptLogoRect(source, value('logoSize'), value('logoPosition'), y);
      canvas.drawImageRect(logo, source, destination, ui.Paint());
      advance(destination.height + 12);
    }
    line(value('businessName'),
        center: true,
        fontSize: size('businessFontSize', 32, 36, 44),
        bold: payload['boldBusinessName'] != false);
    line(value('branchName'), center: true);
    line(value('documentTitle'), center: true, bold: true);
    rule();
    metadata('orderNumber', 'Order #: ');
    metadata('dateTime', 'Date: ');
    metadata('cashierName', 'Cashier: ');
    metadata('tableName', 'Table: ');
    metadata('orderType', 'Type: ');
    rule();
    final columns = receiptColumns(payload);
    void tableRow(Map row, {bool header = false}) {
      if (columns.isEmpty) return;
      var x = receiptMargin;
      var height = 0.0;
      for (final c in columns) {
        var content = header ? c.title : '${row[c.key] ?? ''}';
        if (!header &&
            c.key == 'name' &&
            '${row['variant'] ?? ''}'.isNotEmpty) {
          content = '$content - ${row['variant']}';
        }
        if (!header && (c.key == 'unitPrice' || c.key == 'lineTotal'))
          content = money(content);
        final p = text(content, c.width - 8,
            align: c.align,
            fontSize: header ? body - 4 : body,
            bold: header || c.key == 'lineTotal');
        canvas.drawParagraph(
            p, ui.Offset(x + (c.align == ui.TextAlign.right ? 8 : 0), y));
        height = math.max(height, p.height);
        x += c.width;
      }
      advance(height + (header ? 10 : 14));
    }

    tableRow(const {}, header: true);
    for (final item in payload['items'] as List? ?? const []) {
      tableRow(item as Map);
    }
    rule();
    if (value('subtotal').isNotEmpty)
      pair('Subtotal', money(value('subtotal')));
    if (value('discount').isNotEmpty)
      pair('Discount', money(value('discount')));
    if (value('total').isNotEmpty) {
      rule(heavy: true);
      pair('TOTAL', money(value('total')),
          bold: payload['boldTotal'] != false, fontSize: body + 6);
    }
    final adjusted = (double.tryParse(value('supplemental')) ?? 0) != 0 ||
        (double.tryParse(value('refunded')) ?? 0) != 0;
    if (adjusted) {
      pair(
          'Additional paid',
          money(
              value('supplemental').isEmpty ? '0.00' : value('supplemental')));
      pair('Refunded',
          money(value('refunded').isEmpty ? '0.00' : value('refunded')));
      if (value('netPaid').isNotEmpty)
        pair('Net paid', money(value('netPaid')));
    }
    final payments = payload['payments'] as List? ?? const [];
    if (value('paymentMethod').isNotEmpty ||
        value('tendered').isNotEmpty ||
        value('changeDue').isNotEmpty ||
        (payload['showSplitPayments'] == true && payments.length > 1)) {
      rule();
      if (value('paymentMethod').isNotEmpty)
        pair('Payment', value('paymentMethod').toUpperCase());
      if (payload['showSplitPayments'] == true && payments.length > 1) {
        for (final payment in payments) {
          pair('${payment['method']}', money('${payment['amount']}'));
        }
      }
      if (value('tendered').isNotEmpty)
        pair('Tendered', money(value('tendered')));
      if (value('changeDue').isNotEmpty)
        pair('Change', money(value('changeDue')));
    }
    if (value('footer').trim().isNotEmpty) {
      rule();
      advance(6);
      line(value('footer'),
          center: true,
          fontSize: size('footerFontSize', 22, 26, 30),
          bold: payload['boldFooter'] != false);
    }
    picture = recorder.endRecording();
    return await picture.toImage(receiptDotWidth, y.ceil() + 24);
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    picture?.dispose();
    logo?.dispose();
    for (final p in paragraphs) {
      p.dispose();
    }
  }
}

Future<Uint8List> receiptPreviewPng(Map<String, dynamic> payload) async {
  final image = await renderReceiptImage(payload);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not render receipt preview.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<List<Uint8List>> rasterReceipt(Map<String, dynamic> payload) async {
  final image = await renderReceiptImage(payload);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('Could not render receipt.');
    return encodeReceiptRaster(bytes, image.width, image.height);
  } finally {
    image.dispose();
  }
}

List<Uint8List> encodeReceiptRaster(ByteData rgba, int width, int height) {
  final rowBytes = (width + 7) ~/ 8;
  final bands = <Uint8List>[];
  for (var top = 0; top < height; top += 24) {
    final rows = math.min(24, height - top);
    final band = Uint8List(8 + rowBytes * rows);
    band.setAll(0, [29, 118, 48, 0, rowBytes & 255, rowBytes >> 8, rows, 0]);
    for (var dy = 0; dy < rows; dy++) {
      for (var x = 0; x < width; x++) {
        final offset = ((top + dy) * width + x) * 4;
        final alpha = rgba.getUint8(offset + 3);
        final luminance = (rgba.getUint8(offset) * 299 +
                rgba.getUint8(offset + 1) * 587 +
                rgba.getUint8(offset + 2) * 114) ~/
            1000;
        if ((luminance * alpha + 255 * (255 - alpha)) ~/ 255 < 180) {
          band[8 + dy * rowBytes + x ~/ 8] |= 128 >> (x % 8);
        }
      }
    }
    bands.add(band);
  }
  return bands;
}
