import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
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
}
