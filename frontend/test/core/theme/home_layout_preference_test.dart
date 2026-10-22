import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/theme/home_layout_preference.dart';

class ControlledLayoutStore extends HomeLayoutStore {
  final pending = Completer<void>();
  final writes = <HomeLayout>[];
  @override
  Future<void> save(HomeLayout layout) {
    writes.add(layout);
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all three layouts restore without changing theme or receipt settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'appearance.theme_mode': 'dark',
      'receipt.setting': 'Niradei',
    });
    for (final layout in HomeLayout.values) {
      await HomeLayoutStore().save(layout);
      expect(await HomeLayoutStore().load(), layout);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance.theme_mode'), 'dark');
      expect(prefs.getString('receipt.setting'), 'Niradei');
    }
  });

  test('missing, unknown and malformed layouts safely use Classic', () async {
    expect(await HomeLayoutStore().load(), HomeLayout.classic);
    for (final value in ['future-layout', 99]) {
      SharedPreferences.setMockInitialValues({HomeLayoutStore.key: value});
      expect(await HomeLayoutStore().load(), HomeLayout.classic);
    }
  });

  test('live selection is serialized until persistence completes', () async {
    final store = ControlledLayoutStore();
    final controller = HomeLayoutController(store, HomeLayout.classic);
    addTearDown(controller.dispose);
    final write = controller.select(HomeLayout.modern);
    expect(controller.state.layout, HomeLayout.modern);
    expect(controller.state.saving, isTrue);
    await controller.select(HomeLayout.coffeeCounter);
    expect(store.writes, [HomeLayout.modern]);
    store.pending.complete();
    await write;
    expect(controller.state.saving, isFalse);
  });

  test('save failure restores the previous layout and can retry', () async {
    final store = ControlledLayoutStore();
    final controller = HomeLayoutController(store, HomeLayout.classic);
    addTearDown(controller.dispose);
    final write = controller.select(HomeLayout.coffeeCounter);
    store.pending.completeError(StateError('disk full'));
    await write;
    expect(controller.state.layout, HomeLayout.classic);
    expect(controller.state.error, contains('Could not save'));
    await controller.select(HomeLayout.classic);
    expect(store.writes.length, 2);
    expect(controller.state.saving, isFalse);
  });

  test('disposal while saving does not update an unmounted controller',
      () async {
    final store = ControlledLayoutStore();
    final controller = HomeLayoutController(store, HomeLayout.classic);
    final write = controller.select(HomeLayout.modern);
    controller.dispose();
    store.pending.complete();
    await write;
  });
}
