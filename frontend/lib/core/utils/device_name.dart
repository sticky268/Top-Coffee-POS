import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// A label for the current device/platform, sent as Sanctum's `device_name`
/// on login so tokens are identifiable/revocable per device in the backend.
/// Not a unique device ID — just enough to tell "Android POS terminal" from
/// "iPad kitchen display" in a token list.
String currentDeviceName() {
  if (kIsWeb) return 'web-app';
  if (Platform.isAndroid) return 'android-app';
  if (Platform.isIOS) return 'ios-app';
  if (Platform.isMacOS) return 'macos-app';
  if (Platform.isWindows) return 'windows-app';
  if (Platform.isLinux) return 'linux-app';
  return 'flutter-app';
}
