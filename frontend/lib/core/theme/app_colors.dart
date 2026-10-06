import 'package:flutter/material.dart';

/// Change the brand and semantic palette here. Paper colors are intentionally
/// separate because receipt previews must represent printed ink and paper.
abstract final class AppColors {
  static const espresso = Color(0xFF3E2723);
  static const caramel = Color(0xFFC8A165);
  static const cream = Color(0xFFFAF7F2);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF28201D);
  static const muted = Color(0xFF70615A);
  static const border = Color(0xFFE1D8CD);
  static const softSurface = Color(0xFFF1EAE1);
  static const coffeeContainer = Color(0xFFEEE0D2);
  static const success = Color(0xFF356B4B);
  static const error = Color(0xFFA64040);
  static const warning = Color(0xFF946000);
  static const info = Color(0xFF42677A);
  static const ready = Color(0xFF397368);
  static const plum = Color(0xFF775C7A);
  static const night = Color(0xFF191513);
  static const darkSurface = Color(0xFF241E1B);
  static const darkRaised = Color(0xFF302722);
  static const darkBorder = Color(0xFF5A4B42);
  static const darkText = Color(0xFFF5EEE6);
  static const darkMuted = Color(0xFFC2B4A8);
  static const darkCoffeeContainer = Color(0xFF503A2B);
  static const darkError = Color(0xFFEEA5A1);
  static const darkSuccess = Color(0xFFA0C9AB);
  static const darkWarning = Color(0xFFEAC17A);
  static const darkInfo = Color(0xFFA9C8D7);
  static const darkReady = Color(0xFFA0CEC3);
  static const darkPlum = Color(0xFFD0B6D2);
  static const transparent = Color(0x00000000);
  static const shadow = Color(0xFF251713);
  static const scrim = Color(0x33000000);
  static const receiptInk = Color(0xFF000000);
  static const receiptPaper = Color(0xFFF5F5F5);

  static Color semantic(BuildContext context, Color light) {
    return forScheme(Theme.of(context).colorScheme, light);
  }

  static Color forScheme(ColorScheme scheme, Color light) {
    if (scheme.brightness == Brightness.light) return light;
    if (light == success) return darkSuccess;
    if (light == error) return darkError;
    if (light == warning) return darkWarning;
    if (light == info) return darkInfo;
    if (light == ready) return darkReady;
    if (light == plum) return darkPlum;
    if (light == muted) return darkMuted;
    return light;
  }

  static Color tint(BuildContext context, Color color) => Color.alphaBlend(
    semantic(context, color).withValues(alpha: 0.12),
    Theme.of(context).colorScheme.surface,
  );
}
