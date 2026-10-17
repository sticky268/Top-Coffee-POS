import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'receipt_raster.dart';
export 'receipt_raster.dart' show rasterReceipt, encodeReceiptRaster;

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
