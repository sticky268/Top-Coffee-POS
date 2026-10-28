import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device preference, independent of account, branch and light/dark mode.
enum AppDesign {
  original('Original', 'The familiar Top Coffee design.'),
  coffeeStudio('Coffee Studio',
      'Espresso navigation, teal actions and colorful accents.');

  const AppDesign(this.label, this.description);
  final String label;
  final String description;
}

class AppDesignStore {
  static const key = 'appearance.app_design';

  Future<AppDesign> load() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      return AppDesign.values.firstWhere((layout) => layout.name == value,
          orElse: () => AppDesign.original);
    } catch (_) {
      return AppDesign.original;
    }
  }

  Future<void> save(AppDesign layout) async {
    final saved = await (await SharedPreferences.getInstance())
        .setString(key, layout.name);
    if (!saved) throw StateError('App theme was not saved.');
  }
}

final appDesignStoreProvider = Provider((ref) => AppDesignStore());
final initialAppDesignProvider = Provider((ref) => AppDesign.original);

class AppDesignPreference {
  const AppDesignPreference(this.layout, {this.saving = false, this.error});
  final AppDesign layout;
  final bool saving;
  final String? error;
}

class AppDesignController extends StateNotifier<AppDesignPreference> {
  AppDesignController(this._store, AppDesign initial)
      : super(AppDesignPreference(initial));
  final AppDesignStore _store;

  Future<void> select(AppDesign layout) async {
    if (state.saving || (state.layout == layout && state.error == null)) return;
    final previous = state.layout;
    state = AppDesignPreference(layout, saving: true);
    try {
      await _store.save(layout);
      if (mounted) state = AppDesignPreference(layout);
    } catch (_) {
      if (mounted) {
        state = AppDesignPreference(previous,
            error: 'Could not save app theme. Please try again.');
      }
    }
  }
}

final appDesignPreferenceProvider =
    StateNotifierProvider<AppDesignController, AppDesignPreference>((ref) {
  return AppDesignController(
      ref.watch(appDesignStoreProvider), ref.watch(initialAppDesignProvider));
});
final appDesignProvider = Provider((ref) => ref.watch(
    appDesignPreferenceProvider.select((preference) => preference.layout)));
