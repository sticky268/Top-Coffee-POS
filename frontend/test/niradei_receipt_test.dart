import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/settings/presentation/receipt_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/core/printer/receipt_raster.dart';
import 'package:top_coffee_pos/features/settings/data/receipt_settings.dart';
import 'receipt_settings_audit_test.dart' show settings, receipt;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Niradei')
          ..addFont(rootBundle.load('assets/fonts/Niradei-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Niradei-Black.ttf')))
        .load();
  });

  test('Niradei survives branch settings and reaches the printer payload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final selected = settings(fontStyle: 'Niradei');
    await selected.save(branchKey: 'A');
    final loaded = await ReceiptSettings.load(branchKey: 'A');
    expect(loaded.fontStyle, 'Niradei');
    expect((await ReceiptSettings.load(branchKey: 'B')).fontStyle, 'Default');
    final payload =
        await PrinterService().prepareReceiptWithSettings(receipt(), loaded);
    expect(payload['fontStyle'], 'Niradei');
    expect(receiptFontFamilies('Niradei').first, 'Niradei');
    expect(receiptFontFamilies('Default').first, 'Inter');
  });

  test('Niradei renders Khmer and Latin with Regular and Black receipt text',
      () async {
    final base = await PrinterService()
        .prepareReceiptWithSettings(receipt(), settings(fontStyle: 'Niradei'));
    final directory = Directory('build/ui-polish')..createSync(recursive: true);
    final images = <Uint8List>[];
    for (final bold in [false, true]) {
      final image = await renderReceiptImage({
        ...base,
        'businessName': 'TOP COFFEE កាហ្វេ',
        'footer': 'អរគុណ Thank you',
        'boldBusinessName': bold,
        'boldTotal': bold,
        'boldFooter': bold,
      });
      expect(image.width, receiptDotWidth);
      expect(image.height, greaterThan(100));
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      images.add(bytes);
      File('${directory.path}/receipt-niradei-${bold ? 'black' : 'regular'}.png')
          .writeAsBytesSync(bytes);
      image.dispose();
    }
    expect(images[0], isNot(orderedEquals(images[1])));
  });
  testWidgets(
      'font selector saves Niradei and Test Print uses the selected preview font',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync('niradei-settings-');
    addTearDown(() => directory.deleteSync(recursive: true));
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const printer = MethodChannel('top_coffee_pos/printer');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(printer,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(printer, null);
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      currentBranchProvider.overrideWith(
          (ref) => CurrentBranchNotifier(ref, listenToAuth: false)),
    ], child: const MaterialApp(home: ReceiptSettingsScreen())));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('fontStyleDefault'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Niradei').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fontStyleNiradei')), findsOneWidget);
    final testPrint = find.text('Test Print');
    await tester.ensureVisible(testPrint);
    await tester.pumpAndSettle();
    await tester.tap(testPrint);
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((c) => c.method == 'printReceipt');
    expect((sent.arguments as Map)['fontStyle'], 'Niradei');
    expect(
        calls.map((c) => c.method), ['connect', 'printReceipt', 'disconnect']);
    final save = find.text('Save Settings');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await ReceiptSettings.load()).fontStyle, 'Niradei');
    expect(tester.takeException(), isNull);
  });
}
