import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:top_coffee_pos/core/printer/ios_network_printer.dart';

void main() {
  test('raster bands preserve bit order, alpha and final partial band', () {
    final pixels = Uint8List(8 * 25 * 4);
    // Transparent black must stay white. Opaque black must print.
    pixels[3] = 255;
    pixels[(24 * 8 + 7) * 4 + 3] = 255;
    final bands = encodeReceiptRaster(ByteData.sublistView(pixels), 8, 25);
    expect(bands.length, 2);
    expect(bands.first.sublist(0, 8), [29, 118, 48, 0, 1, 0, 24, 0]);
    expect(bands.first[8], 128);
    expect(bands.last.sublist(0, 8), [29, 118, 48, 0, 1, 0, 1, 0]);
    expect(bands.last[8], 1);
  });

  testWidgets('receipt rendering wraps Unicode and preserves copy content',
      (tester) async {
    final bands = await tester.runAsync(() => rasterReceipt({
          'businessName': 'TOP COFFEE',
          'documentTitle': 'COPY',
          'items': [
            {
              'name': 'កាហ្វេ Coffee ' * 12,
              'quantity': 2,
              'unitPrice': '2.00',
              'lineTotal': '4.00'
            }
          ],
          'total': '4.00',
          'footer': 'សូមអរគុណ',
        }));
    expect(bands, isNotEmpty);
    expect(bands!.every((b) => b[4] == 72 && b[6] <= 24), isTrue);
    expect(bands.any((b) => b.skip(8).any((pixel) => pixel != 0)), isTrue);
  });

  testWidgets('LAN jobs are serialized and drawer pulse is sent once',
      (tester) async {
    await tester.runAsync(() async {
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 9100);
      final received = <int>[];
      Socket? peer;
      final subscription = server.listen((socket) {
        peer = socket;
        socket.listen(received.addAll);
      });
      final printer = IosNetworkPrinter();
      try {
        await printer.invoke('connect', {'ip': '127.0.0.1'});
        await Future.wait([
          printer.invoke('openCashDrawer', null),
          printer.invoke('openCashDrawer', null),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, [27, 112, 0, 30, 255, 27, 112, 0, 30, 255]);
        await printer.invoke('disconnect', null);
        await expectLater(
            printer.invoke('openCashDrawer', null), throwsStateError);
        expect(received.length, 10);
      } finally {
        await printer.invoke('disconnect', null);
        peer?.destroy();
        await subscription.cancel();
        await server.close();
      }
    });
  });

  test('invalid printer destination fails before connecting', () async {
    await expectLater(
        IosNetworkPrinter().invoke('connect', {'ip': 'http://printer:9100'}),
        throwsArgumentError);
  });
}
