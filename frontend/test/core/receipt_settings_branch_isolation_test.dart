import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/features/settings/data/receipt_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt settings stay isolated between branches', () async {
    SharedPreferences.setMockInitialValues({});

    const branchA = ReceiptSettings(
      businessName: 'EZ POS',
      branchName: 'Riverside Receipt',
      logoPosition: 'Center',
      logoSize: 'Medium',
      fontStyle: 'Default',
      bodyFontSize: 'Medium',
      businessFontSize: 'Large',
      footerFontSize: 'Medium',
      boldBusinessName: true,
      boldTotal: true,
      boldFooter: true,
      showOrderNumber: true,
      showDateTime: true,
      showCashier: true,
      showTable: true,
      showOrderType: true,
      showItemName: true,
      showQuantity: true,
      showUnitPrice: true,
      showLineTotal: true,
      showPaymentMethod: true,
      showTendered: true,
      showChange: true,
      showSplitPayments: true,
      footer: 'Riverside footer',
      printerEnabled: true,
      printerIpAddress: '192.168.1.111',
    );

    const branchB = ReceiptSettings(
      businessName: 'EZ POS',
      branchName: 'BKK1 Receipt',
      logoPosition: 'Center',
      logoSize: 'Medium',
      fontStyle: 'Default',
      bodyFontSize: 'Medium',
      businessFontSize: 'Large',
      footerFontSize: 'Medium',
      boldBusinessName: true,
      boldTotal: true,
      boldFooter: true,
      showOrderNumber: true,
      showDateTime: true,
      showCashier: true,
      showTable: true,
      showOrderType: true,
      showItemName: true,
      showQuantity: true,
      showUnitPrice: true,
      showLineTotal: true,
      showPaymentMethod: true,
      showTendered: true,
      showChange: true,
      showSplitPayments: true,
      footer: 'BKK1 footer',
      printerEnabled: true,
      printerIpAddress: '192.168.1.222',
    );

    await branchA.save(branchKey: 'PP-01');
    await branchB.save(branchKey: 'PP-02');

    final loadedA = await ReceiptSettings.load(branchKey: 'PP-01');
    final loadedB = await ReceiptSettings.load(branchKey: 'PP-02');

    expect(loadedA.branchName, 'Riverside Receipt');
    expect(loadedA.footer, 'Riverside footer');
    expect(loadedA.printerIpAddress, '192.168.1.111');

    expect(loadedB.branchName, 'BKK1 Receipt');
    expect(loadedB.footer, 'BKK1 footer');
    expect(loadedB.printerIpAddress, '192.168.1.222');
  });
}
