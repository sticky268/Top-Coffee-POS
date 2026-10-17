import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void>? _receiptFontReady;

Future<void> _loadReceiptFont() => _receiptFontReady ??= () async {
      final loader = FontLoader('TopCoffeeReceiptKhmer')
        ..addFont(rootBundle.load('assets/fonts/NotoSansKhmerUI-Regular.ttf'));
      await loader.load();
    }();

/// ESC/POS LAN transport for iOS. Success means submission, not paper output.
/// Never reconnect or replay bytes after a write starts.
class IosNetworkPrinter {
  Socket? _socket;
  StreamSubscription<Uint8List>? _incoming;
  Object? _failure;
  Future<void> _tail = Future<void>.value();

  Future<void> invoke(String method, Map<String, dynamic>? arguments) {
    final next = _tail.then((_) => _handle(method, arguments ?? {}));
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _disconnect() async {
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    await _incoming?.cancel();
    _incoming = null;
  }

  Future<void> _handle(String method, Map<String, dynamic> payload) async {
    if (method == 'disconnect') {
      await _disconnect();
      return;
    }
    if (method == 'connect') {
      await _disconnect();
      final ip = payload['ip']?.toString().trim() ?? '';
      if (InternetAddress.tryParse(ip) == null) {
        throw ArgumentError('Enter the printer IP address without a port.');
      }
      _failure = null;
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 5),
      );
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      _incoming = socket.listen((_) {}, onError: (Object error) {
        if (identical(_socket, socket)) _failure = error;
        socket.destroy();
      }, onDone: () {
        if (identical(_socket, socket)) {
          _failure ??= StateError('Printer connection closed.');
        }
      });
      // Observe asynchronous sink errors even between jobs.
      unawaited(socket.done.then<void>((_) {}, onError: (Object error) {
        if (identical(_socket, socket)) _failure = error;
      }));
      return;
    }
    if (_socket == null || _failure != null) {
      throw StateError(
          'Printer is not connected. Check its IP and local network access.');
    }
    if (method == 'openCashDrawer') {
      await _write([
        Uint8List.fromList([27, 112, 0, 30, 255])
      ]);
      return;
    }
    if (!const {
      'printReceipt',
      'printReceiptBitmapTest',
      'printTest',
      'printKhmerTest',
      'printBitmapStressTest',
    }.contains(method)) {
      throw UnsupportedError('Unsupported printer method: $method');
    }
    var content = payload;
    if (method == 'printTest' ||
        method == 'printKhmerTest' ||
        method == 'printBitmapStressTest') {
      content = {
        'businessName': 'TOP COFFEE POS',
        'documentTitle': 'PRINTER TEST',
        'footer': 'សួស្តី កាហ្វេ Coffee 123\nសូមអរគុណ',
        'items': List.generate(
            method == 'printBitmapStressTest' ? 40 : 1,
            (i) => {
                  'name': 'LAN printer test ${i + 1}',
                  'quantity': '1',
                  'unitPrice': '',
                  'lineTotal': ''
                }),
      };
    }
    // Finish rendering before transmitting any bytes.
    if (const bool.fromEnvironment('PRINTER_DIAGNOSTICS')) {
      final items = content['items'] as List? ?? const [];
      debugPrint('IOS_PRINTER_ITEMS count=${items.length}');
      for (var index = 0; index < items.length; index++) {
        final row = items[index] as Map;
        debugPrint('IOS_PRINTER_ITEM ${index + 1}: '
            '${row['name']} | qty=${row['quantity']} | total=${row['lineTotal']}');
      }
    }
    final bands = await rasterReceipt(content);
    await _write([
      Uint8List.fromList([27, 64]),
      ...bands,
      Uint8List.fromList([27, 100, 3, 29, 86, 66, 0]),
    ]);
  }

  Future<void> _write(List<Uint8List> parts) async {
    final socket = _socket!;
    try {
      for (final part in parts) {
        for (var offset = 0; offset < part.length; offset += 512) {
          if (_failure != null) throw StateError('Printer connection failed.');
          socket.add(Uint8List.sublistView(
              part, offset, math.min(offset + 512, part.length)));
          await socket.flush().timeout(const Duration(seconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      if (_failure != null) throw StateError('Printer connection failed.');
    } catch (error) {
      await _disconnect();
      throw StateError('Printer submission failed: $error. '
          'Check the paper before making a COPY.');
    }
  }
}

/// 576-dot raster receipts preserve Unicode shaping and avoid printer code pages.
Future<List<Uint8List>> rasterReceipt(Map<String, dynamic> payload) async {
  await _loadReceiptFont();
  const width = 576;
  const inset = 12.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  var y = 12.0;
  final paragraphs = <ui.Paragraph>[];
  String value(String key) => payload[key]?.toString() ?? '';
  double size(String key, double fallback) => switch (value(key)) {
        'Small' => fallback - 4,
        'Large' => fallback + 4,
        _ => fallback,
      };
  final body = size('bodyFontSize', 26);

  void line(String text,
      {double? fontSize, bool bold = false, bool center = false}) {
    if (text.isEmpty) return;
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      textAlign: center ? ui.TextAlign.center : ui.TextAlign.left,
      fontSize: fontSize ?? body,
    ))
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xff000000),
        fontSize: fontSize ?? body,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        fontFamily: 'TopCoffeeReceiptKhmer',
        fontFamilyFallback: const ['Inter'],
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: width - inset * 2));
    paragraphs.add(paragraph);
    canvas.drawParagraph(paragraph, ui.Offset(inset, y));
    y += paragraph.height + 6;
    if (y > 24000)
      throw StateError('Receipt is too long to print. Use an E-Receipt.');
  }

  void field(String key, String label) {
    if (value(key).isNotEmpty) line('$label${value(key)}');
  }

  void rule() {
    y += 6;
    canvas.drawLine(
        ui.Offset(inset, y),
        ui.Offset(width - inset, y),
        ui.Paint()
          ..color = const ui.Color(0xff000000)
          ..strokeWidth = 1);
    y += 12;
  }

  ui.Image? logo;
  ui.Picture? picture;
  ui.Image? image;
  try {
    final logoValue = payload['logoBytes'];
    Uint8List? logoBytes;
    if (logoValue is Uint8List) logoBytes = logoValue;
    if (logoValue is List)
      logoBytes = Uint8List.fromList(logoValue.cast<int>());
    if (logoBytes != null && logoBytes.isNotEmpty) {
      final codec = await ui.instantiateImageCodec(logoBytes, targetWidth: 360);
      try {
        logo = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      final logoWidth = switch (value('logoSize')) {
        'Small' => 120.0,
        'Large' => 300.0,
        _ => 200.0,
      };
      final height = logoWidth * logo.height / logo.width;
      final x = switch (value('logoPosition')) {
        'Left' => inset,
        'Right' => width - inset - logoWidth,
        _ => (width - logoWidth) / 2,
      };
      canvas.drawImageRect(
          logo,
          ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          ui.Rect.fromLTWH(x, y, logoWidth, height),
          ui.Paint());
      y += height + 12;
    }
    line(value('businessName'),
        center: true,
        fontSize: size('businessFontSize', 34),
        bold: payload['boldBusinessName'] != false);
    line(value('branchName'), center: true);
    line(value('documentTitle'), center: true, bold: true);
    field('orderNumber', 'Order: ');
    field('cashierName', 'Cashier: ');
    field('tableName', 'Table: ');
    field('orderType', 'Type: ');
    rule();
    for (final item in (payload['items'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(item as Map);
      line([row['name'], row['variant']]
          .where((v) => v != null && '$v'.isNotEmpty)
          .join(' - '));
      final quantity = row['quantity']?.toString() ?? '';
      final unit = row['unitPrice']?.toString() ?? '';
      final amount = row['lineTotal']?.toString() ?? '';
      line([
        if (quantity.isNotEmpty) 'Qty $quantity',
        if (unit.isNotEmpty) '@ \$$unit',
        if (amount.isNotEmpty) '= \$$amount'
      ].join('  '));
    }
    rule();
    field('subtotal', 'Subtotal: \$');
    field('discount', 'Discount: \$');
    if (value('total').isNotEmpty) {
      line('TOTAL: \$${value('total')}',
          fontSize: body + 6, bold: payload['boldTotal'] != false);
    }
    for (final entry in {
      'supplemental': 'Additional paid',
      'refunded': 'Refunded'
    }.entries) {
      if ((double.tryParse(value(entry.key)) ?? 0) != 0)
        field(entry.key, '${entry.value}: \$');
    }
    field('netPaid', 'Net paid: \$');
    field('paymentMethod', 'Payment: ');
    if (payload['showSplitPayments'] == true) {
      final payments = payload['payments'] as List? ?? const [];
      if (payments.length > 1) {
        for (final payment in payments) {
          line('${payment['method']}: \$${payment['amount']}');
        }
      }
    }
    field('tendered', 'Tendered: \$');
    field('changeDue', 'Change: \$');
    rule();
    line(value('footer'),
        center: true,
        fontSize: size('footerFontSize', 26),
        bold: payload['boldFooter'] != false);
    picture = recorder.endRecording();
    image = await picture.toImage(width, y.ceil() + 12);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) throw StateError('Could not render receipt.');
    return encodeReceiptRaster(rgba, width, image.height);
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    image?.dispose();
    picture?.dispose();
    logo?.dispose();
    for (final paragraph in paragraphs) {
      paragraph.dispose();
    }
  }
}

/// GS v 0 bands, at most 24 rows each; transparent pixels remain white.
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
        final onWhite = (luminance * alpha + 255 * (255 - alpha)) ~/ 255;
        if (onWhite < 180) band[8 + dy * rowBytes + x ~/ 8] |= 128 >> (x % 8);
      }
    }
    bands.add(band);
  }
  return bands;
}
