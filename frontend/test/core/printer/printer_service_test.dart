import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const printer = MethodChannel('top_coffee_pos/printer');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
        paths, (_) async => Directory.systemTemp.path);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(printer, null);
    messenger.setMockMethodCallHandler(paths, null);
  });

  test('a printer rejection is surfaced so the cashier can retry', () async {
    messenger.setMockMethodCallHandler(printer, (_) async => false);
    await expectLater(
        PrinterService().printTest(), throwsA(isA<PlatformException>()));
    messenger.setMockMethodCallHandler(printer, (_) async => true);
    await expectLater(PrinterService().printTest(), completes);
  });

  test('receipt bridge receives saved quantities, total, tendered and change',
      () async {
    Map<dynamic, dynamic>? payload;
    messenger.setMockMethodCallHandler(printer, (call) async {
      if (call.method == 'printReceipt') payload = call.arguments as Map;
      return true;
    });
    await PrinterService().printReceipt(const OrderReceipt(
      orderId: 42,
      uuid: 'receipt-42',
      orderType: 'takeaway',
      status: 'completed',
      subtotal: 7,
      discountTotal: 0,
      total: 7,
      branchCode: 'TEST-PRINTER',
      items: [
        OpenOrderItem(
            id: 1,
            productName: 'Coffee',
            variantName: null,
            quantity: 2,
            unitPrice: 3.5,
            lineTotal: 7)
      ],
      payment: PaymentConfirmation(
          id: 1,
          method: 'cash',
          amount: 7,
          tendered: 10,
          changeDue: 3,
          status: 'completed'),
    ));
    expect(payload!['total'], '7.00');
    expect(payload!['tendered'], '10.00');
    expect(payload!['changeDue'], '3.00');
    expect((payload!['items'] as List).single['quantity'], 2);
  });
}
