import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/theme/theme_preference.dart';
import 'package:top_coffee_pos/features/settings/presentation/settings_screen.dart';

import 'ui_polish_test.dart' show savePreview;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in [('Inter', 'assets/fonts/Inter.ttf'), ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<ProviderContainer> pump(WidgetTester tester, Size size, double scale, ThemeMode mode, {GlobalKey? preview}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [initialThemeModeProvider.overrideWithValue(mode)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) => MaterialApp(
        theme: AppTheme.light, darkTheme: AppTheme.dark,
        themeMode: ref.watch(themeModeProvider),
        home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: preview, child: const SettingsScreen())),
      )),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  for (final size in [const Size(360, 800), const Size(800, 1280)]) {
    for (final scale in [1.0, 2.0]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('appearance fits $size text $scale $mode and retains settings access', (tester) async {
          final preview = GlobalKey();
          await pump(tester, size, scale, mode, preview: preview);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const ValueKey('appearance-system')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('appearance-system')).hitTestable(), findsOneWidget);
          if (scale == 1) {
            await savePreview(tester, preview, 'appearance-${size.width.toInt()}-${mode.name}');
          }
          await tester.scrollUntilVisible(find.text('Receipt Settings'), 250);
          await tester.pumpAndSettle();
          expect(find.text('Receipt Settings').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('appearance choices apply and persist through the settings controls', (tester) async {
    final container = await pump(tester, const Size(360, 800), 1, ThemeMode.system);
    for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      final choice = find.byKey(ValueKey('appearance-${mode.name}'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), mode);
      expect(await ThemePreferenceStore().load(), mode);
      expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    }
  });
}
