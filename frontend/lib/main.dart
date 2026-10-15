import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/theme/theme_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.validateProductionUrl(environment: kReleaseMode ? 'prod' : Env.flavor);
  final themeStore = ThemePreferenceStore();
  final themeMode = await themeStore.load();
  runApp(ProviderScope(
    overrides: [
      themePreferenceStoreProvider.overrideWithValue(themeStore),
      initialThemeModeProvider.overrideWithValue(themeMode),
    ],
    child: const TopCoffeeApp(),
  ));
}
