import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

/// Opt-in presentation only; Original continues to use AppTheme unchanged.
class CoffeeStudioStyle extends ThemeExtension<CoffeeStudioStyle> {
  const CoffeeStudioStyle();
  @override
  CoffeeStudioStyle copyWith() => this;
  @override
  CoffeeStudioStyle lerp(covariant CoffeeStudioStyle? other, double t) => this;
}

abstract final class CoffeeStudioTheme {
  static bool active(BuildContext context) =>
      Theme.of(context).extension<CoffeeStudioStyle>() != null;
  static Color accentSurface(BuildContext context, int index) {
    const colors = [
      Color(0xFF168372),
      Color(0xFFC4594C),
      Color(0xFF7555A6),
      Color(0xFF146CB5),
      Color(0xFFA96700)
    ];
    return Color.alphaBlend(
        colors[index.abs() % colors.length].withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .20 : .09),
        Theme.of(context).colorScheme.surface);
  }

  static ThemeData get light => _build(false);
  static ThemeData get dark => _build(true);

  static ThemeData _build(bool dark) {
    final original = dark ? AppTheme.dark : AppTheme.light;
    final scheme = original.colorScheme.copyWith(
      primary: dark ? const Color(0xFFA0CEC3) : const Color(0xFF145A52),
      onPrimary: dark ? const Color(0xFF102E29) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF214A43) : const Color(0xFFE0F1EB),
      onPrimaryContainer:
          dark ? const Color(0xFFC8EBDE) : const Color(0xFF145A52),
      secondaryContainer:
          dark ? const Color(0xFF503A2B) : const Color(0xFFF4E5CD),
      tertiary: dark ? const Color(0xFFD0B6D2) : const Color(0xFF775C7A),
    );
    final header = original.appBarTheme.copyWith(
      backgroundColor: AppColors.espresso,
      foregroundColor: AppColors.white,
      titleTextStyle: original.textTheme.titleLarge
          ?.copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
      iconTheme: const IconThemeData(color: AppColors.white),
      actionsIconTheme: const IconThemeData(color: AppColors.white),
    );
    return original.copyWith(
      colorScheme: scheme,
      extensions: const [CoffeeStudioStyle()],
      appBarTheme: header,
      cardTheme: original.cardTheme.copyWith(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: original.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: original.filledButtonTheme.style?.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: .12)
                  : scheme.primary),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: .38)
                  : scheme.onPrimary),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      chipTheme: original.chipTheme.copyWith(
        selectedColor: scheme.primaryContainer,
      ),
      listTileTheme: original.listTileTheme.copyWith(
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        dividerThickness: 1,
        headingTextStyle: original.textTheme.labelLarge,
        dataTextStyle: original.textTheme.bodyMedium,
      ),
    );
  }

  /// A local palette for navigation only, independent of the content's mode.
  static ThemeData navigation(ThemeData content) => content.copyWith(
        colorScheme: content.colorScheme.copyWith(
          surface: AppColors.espresso,
          onSurface: AppColors.white,
          onSurfaceVariant: const Color(0xFFE1D8CD),
          primary: AppColors.caramel,
          onPrimary: AppColors.espresso,
          primaryContainer: const Color(0xFF765332),
          onPrimaryContainer: AppColors.white,
          outlineVariant: const Color(0xFF61483E),
        ),
        textTheme: content.textTheme
            .apply(bodyColor: AppColors.white, displayColor: AppColors.white),
      );
}
