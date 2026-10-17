import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:top_coffee_pos/core/printer/receipt_raster.dart';

void main() {
  final payload = <String, dynamic>{
    'businessName': 'TOP COFFEE',
    'branchName': 'Riverside',
    'documentTitle': 'COPY',
    'orderNumber': 'PP-01-000132',
    'dateTime': '17/10/2026 11:43 AM',
    'showItemName': true,
    'showQuantity': true,
    'showUnitPrice': true,
    'showLineTotal': true,
    'items': [
      {
        'name': 'កាហ្វេ',
        'quantity': '1',
        'unitPrice': '5.00',
        'lineTotal': '5.00'
      },
      {
        'name': 'Green Tea',
        'quantity': '1',
        'unitPrice': '2.50',
        'lineTotal': '2.50'
      },
      {
        'name': 'Iced Latte',
        'quantity': '1',
        'unitPrice': '3.50',
        'lineTotal': '3.50'
      },
    ],
    'subtotal': '11.00',
    'discount': '0.00',
    'total': '11.00',
    'paymentMethod': 'Cash',
    'tendered': '15.00',
    'changeDue': '4.00',
    'footer': 'សូមអរគុណ Thank you!',
  };

  test('four columns fit the thermal paper and align amounts right', () {
    final columns = receiptColumns(payload);
    expect(columns.map((c) => c.key),
        ['name', 'quantity', 'unitPrice', 'lineTotal']);
    expect(columns.fold<double>(0, (sum, c) => sum + c.width),
        receiptContentWidth);
    expect(columns.last.align, ui.TextAlign.right);
    expect(columns.first.width, greaterThan(200));
  });

  test('hidden columns leave no headings or reserved whitespace', () {
    final columns = receiptColumns(
        {...payload, 'showQuantity': false, 'showUnitPrice': false});
    expect(columns.map((c) => c.key), ['name', 'lineTotal']);
    expect(columns.first.width, receiptContentWidth - columns.last.width);
    expect(
        receiptColumns({
          ...payload,
          'showItemName': false,
          'showQuantity': false,
          'showUnitPrice': false,
          'showLineTotal': false
        }),
        isEmpty);
  });

  test('old saved jobs infer visible columns from their original fields', () {
    expect(
        receiptColumns({
          'items': [
            {
              'name': 'Coffee',
              'quantity': '',
              'unitPrice': '',
              'lineTotal': '5.00'
            }
          ]
        }).map((c) => c.key),
        ['name', 'lineTotal']);
  });

  testWidgets('preview pixels and printer raster contain the same receipt',
      (tester) async {
    await tester.runAsync(() async {
      final png = await receiptPreviewPng(payload);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        final pixels =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final expected =
            encodeReceiptRaster(pixels!, image.width, image.height);
        final actual = await rasterReceipt(payload);
        expect(image.width, 576);
        expect(actual, expected);
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('long Khmer item names wrap instead of clipping rows',
      (tester) async {
    await tester.runAsync(() async {
      final short = await renderReceiptImage(payload);
      final long = await renderReceiptImage({
        ...payload,
        'items': [
          {
            'name': 'កាហ្វេ Latte with extra milk ' * 12,
            'quantity': '1',
            'unitPrice': '12345.67',
            'lineTotal': '12345.67'
          },
          ...(payload['items'] as List).skip(1),
        ]
      });
      try {
        expect(long.height, greaterThan(short.height + 100));
      } finally {
        short.dispose();
        long.dispose();
      }
    });
  });
}
