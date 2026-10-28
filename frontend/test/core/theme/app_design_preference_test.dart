import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/theme/app_design_preference.dart';

class ControlledDesignStore extends AppDesignStore {
  final pending = Completer<void>();
  final writes = <AppDesign>[];
  @override
  Future<void> save(AppDesign layout) {
    writes.add(layout);
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('both designs restore without changing theme or receipt settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'appearance.theme_mode': 'dark',
      'receipt.setting': 'Niradei',
    });
    for (final layout in AppDesign.values) {
      await AppDesignStore().save(layout);
      expect(await AppDesignStore().load(), layout);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance.theme_mode'), 'dark');
      expect(prefs.getString('receipt.setting'), 'Niradei');
    }
  });

  test('missing, unknown and malformed layouts safely use Original', () async {
    expect(await AppDesignStore().load(), AppDesign.original);
    for (final value in ['future-layout', 99]) {
      SharedPreferences.setMockInitialValues({AppDesignStore.key: value});
      expect(await AppDesignStore().load(), AppDesign.original);
    }
  });

  test('live selection is serialized until persistence completes', () async {
    final store = ControlledDesignStore();
    final controller = AppDesignController(store, AppDesign.original);
    addTearDown(controller.dispose);
    final write = controller.select(AppDesign.coffeeStudio);
    expect(controller.state.layout, AppDesign.coffeeStudio);
    expect(controller.state.saving, isTrue);
    await controller.select(AppDesign.original);
    expect(store.writes, [AppDesign.coffeeStudio]);
    store.pending.complete();
    await write;
    expect(controller.state.saving, isFalse);
  });

  test('save failure restores the previous layout and can retry', () async {
    final store = ControlledDesignStore();
    final controller = AppDesignController(store, AppDesign.original);
    addTearDown(controller.dispose);
    final write = controller.select(AppDesign.coffeeStudio);
    store.pending.completeError(StateError('disk full'));
    await write;
    expect(controller.state.layout, AppDesign.original);
    expect(controller.state.error, contains('Could not save'));
    await controller.select(AppDesign.original);
    expect(store.writes.length, 2);
    expect(controller.state.saving, isFalse);
  });

  test('disposal while saving does not update an unmounted controller',
      () async {
    final store = ControlledDesignStore();
    final controller = AppDesignController(store, AppDesign.original);
    final write = controller.select(AppDesign.coffeeStudio);
    controller.dispose();
    store.pending.complete();
    await write;
  });
}
