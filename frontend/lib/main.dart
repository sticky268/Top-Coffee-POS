import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/theme/theme_preference.dart';
import 'core/theme/home_layout_preference.dart';
import 'core/theme/app_design_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.validateProductionUrl(environment: kReleaseMode ? 'prod' : Env.flavor);
  final themeStore = ThemePreferenceStore();
  final themeMode = await themeStore.load();
  final layoutStore = HomeLayoutStore();
  final homeLayout = await layoutStore.load();
  final designStore = AppDesignStore();
  final design = await designStore.load();
  runApp(ProviderScope(
    overrides: [
      appDesignStoreProvider.overrideWithValue(designStore),
      initialAppDesignProvider.overrideWithValue(design),
      homeLayoutStoreProvider.overrideWithValue(layoutStore),
      initialHomeLayoutProvider.overrideWithValue(homeLayout),
      themePreferenceStoreProvider.overrideWithValue(themeStore),
      initialThemeModeProvider.overrideWithValue(themeMode),
    ],
    child: const TopCoffeeApp(),
  ));
}
