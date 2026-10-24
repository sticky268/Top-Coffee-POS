import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/theme/app_design_preference.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:top_coffee_pos/features/settings/presentation/app_design_settings_card.dart';
import 'ui_polish_test.dart' show savePreview;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'theme selection and Original restoration dark=$dark scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preview = GlobalKey();
        await tester.pumpWidget(ProviderScope(child: Consumer(
          builder: (context, ref, _) {
            final design = ref.watch(appDesignProvider);
            return MaterialApp(
              theme: design == AppDesign.original
                  ? (dark ? AppTheme.dark : AppTheme.light)
                  : (dark ? CoffeeStudioTheme.dark : CoffeeStudioTheme.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: preview, child: child!),
              ),
              home: Scaffold(
                appBar: AppBar(title: const Text('Settings')),
                body: const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: AppDesignSettingsCard()),
              ),
            );
          },
        )));
        await tester.pumpAndSettle();
        final original =
            Theme.of(tester.element(find.byType(AppDesignSettingsCard)));
        await tester.ensureVisible(
            find.byKey(const ValueKey('app-design-coffeeStudio')));
        await tester.tap(find.byKey(const ValueKey('app-design-coffeeStudio')));
        await tester.pumpAndSettle();
        final studio =
            Theme.of(tester.element(find.byType(AppDesignSettingsCard)));
        expect(studio.extension<CoffeeStudioStyle>(), isNotNull);
        expect(studio.colorScheme.primary, isNot(original.colorScheme.primary));
        expect(
            (await SharedPreferences.getInstance())
                .getString(AppDesignStore.key),
            'coffeeStudio');
        expect(tester.takeException(), isNull);
        await savePreview(tester, preview, 'app-theme-$dark-$scale');
        await tester
            .ensureVisible(find.byKey(const ValueKey('app-design-original')));
        await tester.tap(find.byKey(const ValueKey('app-design-original')));
        await tester.pumpAndSettle();
        final restored =
            Theme.of(tester.element(find.byType(AppDesignSettingsCard)));
        expect(restored.extension<CoffeeStudioStyle>(), isNull);
        expect(restored.colorScheme, original.colorScheme);
        expect(restored.textTheme, original.textTheme);
        expect(
            restored.scaffoldBackgroundColor, original.scaffoldBackgroundColor);
        expect(restored.appBarTheme, original.appBarTheme);
        expect(restored.cardTheme, original.cardTheme);
        expect(restored.inputDecorationTheme, original.inputDecorationTheme);
        expect(restored.filledButtonTheme.style?.backgroundColor?.resolve({}),
            original.filledButtonTheme.style?.backgroundColor?.resolve({}));
      });
    }
  }
}
