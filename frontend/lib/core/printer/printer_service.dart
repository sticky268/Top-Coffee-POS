import 'package:flutter/services.dart';

class PrinterService {
  static const MethodChannel _channel = MethodChannel(
    'top_coffee_pos/printer',
  );

  Future<void> connect(String ipAddress) async {
    await _channel.invokeMethod<bool>(
      'connect',
      <String, dynamic>{
        'ip': ipAddress,
      },
    );
  }

  Future<void> printTest() async {
    await _channel.invokeMethod<bool>('printTest');
  }

  Future<void> disconnect() async {
    await _channel.invokeMethod<bool>('disconnect');
  }
}