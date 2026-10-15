import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-wide appearance; it is independent of account and branch changes.
class ThemePreferenceStore {
  static const key = 'appearance.theme_mode';

  Future<ThemeMode> load() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // Appearance storage must not prevent the cashier from opening the app.
      return ThemeMode.system;
    }
  }

  Future<void> save(ThemeMode mode) async {
    final saved = await (await SharedPreferences.getInstance())
        .setString(key, mode.name);
    if (!saved) throw StateError('Appearance preference was not saved.');
  }
}

final themePreferenceStoreProvider = Provider((ref) => ThemePreferenceStore());

// main loads this before the first frame to avoid flashing the wrong theme.
final initialThemeModeProvider = Provider((ref) => ThemeMode.system);

class ThemePreference {
  const ThemePreference(this.mode, {this.saving = false, this.error});
  final ThemeMode mode;
  final bool saving;
  final String? error;
}

class ThemePreferenceController extends StateNotifier<ThemePreference> {
  ThemePreferenceController(this._store, ThemeMode initialMode)
      : super(ThemePreference(initialMode));

  final ThemePreferenceStore _store;

  Future<void> select(ThemeMode mode) async {
    if (state.saving || (state.mode == mode && state.error == null)) return;
    final previous = state.mode;
    state = ThemePreference(mode, saving: true);
    try {
      await _store.save(mode);
      if (mounted) state = ThemePreference(mode);
    } catch (_) {
      if (mounted) {
        state = ThemePreference(previous,
            error: 'Could not save appearance. Please try again.');
      }
    }
  }
}

final themePreferenceProvider =
    StateNotifierProvider<ThemePreferenceController, ThemePreference>((ref) {
  return ThemePreferenceController(ref.watch(themePreferenceStoreProvider),
      ref.watch(initialThemeModeProvider));
});

final themeModeProvider = Provider(
    (ref) => ref.watch(themePreferenceProvider.select((state) => state.mode)));
