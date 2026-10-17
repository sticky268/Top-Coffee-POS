import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/core/printer/receipt_raster.dart';
import 'package:top_coffee_pos/core/printer/receipt_raster_pdf.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/settings/data/receipt_settings.dart';

ReceiptSettings settings(
    {Map<String, bool> flags = const {},
    String logoSize = 'Large',
    String logoPosition = 'Right',
    String fontStyle = 'Serif'}) {
  bool flag(String key) => flags[key] ?? true;
  return ReceiptSettings(
    businessName: 'Test កាហ្វេ',
    branchName: 'Branch A',
    showLogo: false,
    logoSize: logoSize,
    logoPosition: logoPosition,
    fontStyle: fontStyle,
    bodyFontSize: 'Small',
    businessFontSize: 'Medium',
    footerFontSize: 'Large',
    boldBusinessName: false,
    boldTotal: false,
    boldFooter: false,
    showOrderNumber: flag('orderNumber'),
    showDateTime: flag('dateTime'),
    showCashier: flag('cashierName'),
    showTable: flag('tableName'),
    showOrderType: flag('orderType'),
    showItemName: flag('name'),
    showQuantity: flag('quantity'),
    showUnitPrice: flag('unitPrice'),
    showLineTotal: flag('lineTotal'),
    showPaymentMethod: flag('paymentMethod'),
    showTendered: flag('tendered'),
    showChange: flag('changeDue'),
    showSplitPayments: flag('showSplitPayments'),
    footer: '',
    printerEnabled: false,
    printerIpAddress: '192.168.1.55',
  );
}

List<Object> values(ReceiptSettings s) => [
      s.businessName,
      s.branchName,
      s.showLogo,
      s.logoPosition,
      s.logoSize,
      s.fontStyle,
      s.bodyFontSize,
      s.businessFontSize,
      s.footerFontSize,
      s.boldBusinessName,
      s.boldTotal,
      s.boldFooter,
      s.showOrderNumber,
      s.showDateTime,
      s.showCashier,
      s.showTable,
      s.showOrderType,
      s.showItemName,
      s.showQuantity,
      s.showUnitPrice,
      s.showLineTotal,
      s.showPaymentMethod,
      s.showTendered,
      s.showChange,
      s.showSplitPayments,
      s.footer,
      s.printerEnabled,
      s.printerIpAddress,
    ];

OrderReceipt receipt({bool split = false}) => OrderReceipt(
      orderId: 132,
      uuid: 'audit-receipt',
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 5,
      discountTotal: 0,
      total: 5,
      branchCode: 'A',
      cashierName: 'Admin',
      tableName: 'T3',
      createdAt: DateTime(2026, 10, 17, 11, 43),
      items: const [
        OpenOrderItem(
            id: 1,
            productName: 'កាហ្វេ',
            variantName: 'Large',
            quantity: 1,
            unitPrice: 5,
            lineTotal: 5)
      ],
      payments: split
          ? const [
              PaymentConfirmation(
                  id: 1, method: 'cash', amount: 2, status: 'completed'),
              PaymentConfirmation(
                  id: 2, method: 'card', amount: 3, status: 'completed'),
            ]
          : const [
              PaymentConfirmation(
                  id: 1,
                  method: 'cash',
                  amount: 5,
                  tendered: 10,
                  changeDue: 5,
                  status: 'completed')
            ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all 28 receipt settings survive saving and reloading', () async {
    final original = settings(flags: {
      for (final key in [
        'orderNumber',
        'dateTime',
        'cashierName',
        'tableName',
        'orderType',
        'name',
        'quantity',
        'unitPrice',
        'lineTotal',
        'paymentMethod',
        'tendered',
        'changeDue',
        'showSplitPayments'
      ])
        key: false,
    });
    await original.save(branchKey: 'A');
    expect(
        values(await ReceiptSettings.load(branchKey: 'A')), values(original));
    expect(values(original).length, 28);
  });

  test('branch preferences do not leak and size/style choices round-trip',
      () async {
    for (final size in ['Small', 'Medium', 'Large']) {
      for (final style in ['Default', 'Sans Serif', 'Serif', 'Monospace']) {
        for (final position in ['Left', 'Center', 'Right']) {
          final original = settings(
              logoSize: size, fontStyle: style, logoPosition: position);
          await original.save(branchKey: 'A');
          expect(values(await ReceiptSettings.load(branchKey: 'A')),
              values(original));
        }
      }
    }
    final other = await ReceiptSettings.load(
        branchKey: 'B', branchNameFallback: 'Branch B');
    expect(other.branchName, 'Branch B');
    expect(other.showLogo, isTrue);
    expect(other.printerEnabled, isTrue);
    expect(other.printerIpAddress, ReceiptSettings.defaultPrinterIpAddress);
  });

  for (final field in [
    'orderNumber',
    'dateTime',
    'cashierName',
    'tableName',
    'orderType',
    'name',
    'quantity',
    'unitPrice',
    'lineTotal',
    'paymentMethod',
    'tendered',
    'changeDue'
  ]) {
    test('$field switch hides only its receipt field', () async {
      final service = PrinterService();
      final original =
          await service.prepareReceiptWithSettings(receipt(), settings());
      final selected = settings(flags: {field: false});
      await selected.save(branchKey: 'A');
      final reloaded = await ReceiptSettings.load(branchKey: 'A');
      expect(values(reloaded), values(selected));
      final hidden =
          await service.prepareReceiptWithSettings(receipt(), reloaded);
      if (['name', 'quantity', 'unitPrice', 'lineTotal'].contains(field)) {
        expect((hidden['items'] as List).single[field], '');
        expect((original['items'] as List).single[field], isNot(''));
      } else {
        expect(hidden[field], anyOf('', isNull));
        expect(original[field], isNot(anyOf('', isNull)));
      }
      expect(hidden['total'], '5.00');
      expect(hidden['items'], hasLength(1));
    });
  }

  test('fonts, bold switches, logo visibility and footer reach the renderer',
      () async {
    final payload = await PrinterService()
        .prepareReceiptWithSettings(receipt(), settings());
    expect(payload['fontStyle'], 'Serif');
    expect(payload['bodyFontSize'], 'Small');
    expect(payload['businessFontSize'], 'Medium');
    expect(payload['footerFontSize'], 'Large');
    for (final key in [
      'showLogo',
      'boldBusinessName',
      'boldTotal',
      'boldFooter'
    ]) {
      expect(payload[key], isFalse);
    }
    expect(payload['logoBytes'], isNull);
    expect(payload['footer'], '');
    expect(payload['dateTime'], '17/10/2026 11:43 AM');
  });

  test('split breakdown can hide without losing saved payment information',
      () async {
    final payload = await PrinterService().prepareReceiptWithSettings(
        receipt(split: true), settings(flags: {'showSplitPayments': false}));
    expect(payload['showSplitPayments'], isFalse);
    expect(payload['paymentMethod'], 'Split');
    expect(payload['payments'], hasLength(2));
    expect(payload['tendered'], isNull);
    expect(payload['changeDue'], isNull);
  });

  test('all logo shapes have three distinct sizes and stay inside the paper',
      () {
    for (final shape in [
      const ui.Rect.fromLTWH(0, 0, 20, 1000),
      const ui.Rect.fromLTWH(0, 0, 1000, 20),
      const ui.Rect.fromLTWH(0, 0, 100, 100)
    ]) {
      var previous = 0.0;
      for (final size in ['Small', 'Medium', 'Large']) {
        final rect = receiptLogoRect(shape, size, 'Center', 24);
        expect(rect.width * rect.height, greaterThan(previous));
        previous = rect.width * rect.height;
        expect(rect.left, greaterThanOrEqualTo(receiptMargin));
        expect(rect.right, lessThanOrEqualTo(receiptDotWidth - receiptMargin));
        expect(rect.width / rect.height,
            closeTo(shape.width / shape.height, 0.00001));
      }
      expect(receiptLogoRect(shape, 'Large', 'Left', 24).left, receiptMargin);
      expect(receiptLogoRect(shape, 'Large', 'Right', 24).right,
          receiptDotWidth - receiptMargin);
    }
  });

  test('logo sizing ignores empty white/transparent padding', () {
    final bytes = Uint8List(10 * 10 * 4)..fillRange(0, 10 * 10 * 4, 255);
    const offset = (4 * 10 + 5) * 4;
    bytes[offset] = bytes[offset + 1] = bytes[offset + 2] = 0;
    expect(receiptLogoInkBounds(ByteData.sublistView(bytes), 10, 10),
        const ui.Rect.fromLTWH(5, 4, 1, 1));
    expect(receiptLogoInkBounds(ByteData.sublistView(Uint8List(400)), 10, 10),
        const ui.Rect.fromLTWH(0, 0, 10, 10));
  });

  testWidgets('font sizes and independent bold switches change rendered output',
      (tester) async {
    await tester.runAsync(() async {
      final payload = await PrinterService()
          .prepareReceiptWithSettings(receipt(), settings());
      payload['footer'] = 'Thank you!';
      final baseline = await receiptPreviewPng(payload);
      for (final change in <Map<String, dynamic>>[
        {'bodyFontSize': 'Large'},
        {'businessFontSize': 'Large'},
        {'footerFontSize': 'Small'},
        {'boldBusinessName': true},
        {'boldTotal': true},
        {'boldFooter': true},
      ]) {
        final updated = await receiptPreviewPng({...payload, ...change});
        expect(updated, isNot(orderedEquals(baseline)), reason: '$change');
      }
    });
  });

  testWidgets(
      'split display switch changes preview and PDF uses shared renderer',
      (tester) async {
    await tester.runAsync(() async {
      final payload = await PrinterService()
          .prepareReceiptWithSettings(receipt(split: true), settings());
      final shown = await renderReceiptImage(payload);
      final hidden =
          await renderReceiptImage({...payload, 'showSplitPayments': false});
      try {
        expect(shown.height, greaterThan(hidden.height));
      } finally {
        shown.dispose();
        hidden.dispose();
      }
      final pdf = await receiptRasterPdf(payload);
      expect(latin1.decode(pdf.take(5).toList()), '%PDF-');
    });
  });
}
