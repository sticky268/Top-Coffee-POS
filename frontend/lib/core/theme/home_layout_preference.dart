import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device preference, independent of account, branch and light/dark mode.
enum HomeLayout {
  classic('Classic', 'A familiar dashboard with organized shortcuts.'),
  modern('Modern', 'A spacious dashboard with sales in focus.'),
  coffeeCounter(
      'Coffee Counter', 'Colorful shortcuts for everyday coffee shop tasks.');

  const HomeLayout(this.label, this.description);
  final String label;
  final String description;
}

class HomeLayoutStore {
  static const key = 'appearance.home_layout';

  Future<HomeLayout> load() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      return HomeLayout.values.firstWhere((layout) => layout.name == value,
          orElse: () => HomeLayout.classic);
    } catch (_) {
      return HomeLayout.classic;
    }
  }

  Future<void> save(HomeLayout layout) async {
    final saved = await (await SharedPreferences.getInstance())
        .setString(key, layout.name);
    if (!saved) throw StateError('Home layout was not saved.');
  }
}

final homeLayoutStoreProvider = Provider((ref) => HomeLayoutStore());
final initialHomeLayoutProvider = Provider((ref) => HomeLayout.classic);

class HomeLayoutPreference {
  const HomeLayoutPreference(this.layout, {this.saving = false, this.error});
  final HomeLayout layout;
  final bool saving;
  final String? error;
}

class HomeLayoutController extends StateNotifier<HomeLayoutPreference> {
  HomeLayoutController(this._store, HomeLayout initial)
      : super(HomeLayoutPreference(initial));
  final HomeLayoutStore _store;

  Future<void> select(HomeLayout layout) async {
    if (state.saving || (state.layout == layout && state.error == null)) return;
    final previous = state.layout;
    state = HomeLayoutPreference(layout, saving: true);
    try {
      await _store.save(layout);
      if (mounted) state = HomeLayoutPreference(layout);
    } catch (_) {
      if (mounted) {
        state = HomeLayoutPreference(previous,
            error: 'Could not save home layout. Please try again.');
      }
    }
  }
}

final homeLayoutPreferenceProvider =
    StateNotifierProvider<HomeLayoutController, HomeLayoutPreference>((ref) {
  return HomeLayoutController(
      ref.watch(homeLayoutStoreProvider), ref.watch(initialHomeLayoutProvider));
});
final homeLayoutProvider = Provider((ref) => ref.watch(
    homeLayoutPreferenceProvider.select((preference) => preference.layout)));
