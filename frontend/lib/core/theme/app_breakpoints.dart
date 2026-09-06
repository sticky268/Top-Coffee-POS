import 'package:flutter/widgets.dart';

/// Screen-size breakpoints used across the POS UI (Phase 5) to switch
/// between phone/tablet/large-tablet grid layouts.
class AppBreakpoints {
  AppBreakpoints._();

  static const double tablet = 600;
  static const double largeTablet = 1024;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tablet;

  static bool isLargeTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= largeTablet;
}
