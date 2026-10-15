import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/routing/app_router.dart';
import 'package:top_coffee_pos/core/theme/theme_preference.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';

class AppearanceAuthRepository extends Mock implements AuthRepository {}

class ControlledThemeStore extends ThemePreferenceStore {
  final writes = <ThemeMode>[];
  final pending = Completer<void>();
  @override
  Future<void> save(ThemeMode mode) {
    writes.add(mode);
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved appearance restores in a fresh store without clearing other preferences', () async {
    SharedPreferences.setMockInitialValues({'receipt.setting': 'unchanged'});
    for (final mode in ThemeMode.values) {
      await ThemePreferenceStore().save(mode);
      expect(await ThemePreferenceStore().load(), mode);
      expect((await SharedPreferences.getInstance()).getString('receipt.setting'), 'unchanged');
    }
  });

  test('new and unrecognized preferences follow the device', () async {
    expect(await ThemePreferenceStore().load(), ThemeMode.system);
    SharedPreferences.setMockInitialValues({ThemePreferenceStore.key: 'invalid'});
    expect(await ThemePreferenceStore().load(), ThemeMode.system);
  });

  test('selection updates immediately and rejects concurrent writes', () async {
    final store = ControlledThemeStore();
    final controller = ThemePreferenceController(store, ThemeMode.system);
    addTearDown(controller.dispose);
    final saving = controller.select(ThemeMode.dark);
    expect(controller.state.mode, ThemeMode.dark);
    expect(controller.state.saving, isTrue);
    await controller.select(ThemeMode.light);
    expect(store.writes, [ThemeMode.dark]);
    store.pending.complete();
    await saving;
    expect(controller.state.saving, isFalse);
    expect(controller.state.error, isNull);
  });

  test('storage failure restores the previous choice with a retryable error', () async {
    final store = ControlledThemeStore();
    final controller = ThemePreferenceController(store, ThemeMode.light);
    addTearDown(controller.dispose);
    final saving = controller.select(ThemeMode.dark);
    store.pending.completeError(StateError('Disk unavailable'));
    await saving;
    expect(controller.state.mode, ThemeMode.light);
    expect(controller.state.saving, isFalse);
    expect(controller.state.error, contains('try again'));
  });

  testWidgets('app starts in the saved theme and switching preserves router and form state', (tester) async {
    final auth = AppearanceAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: const TopCoffeeApp()));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(TextFormField).first)).brightness, Brightness.dark);
    await tester.enterText(find.byType(TextFormField).first, 'cashier@example.invalid');
    final router = container.read(appRouterProvider);
    await container.read(themePreferenceProvider.notifier).select(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(TextFormField).first)).brightness, Brightness.light);
    expect(find.text('cashier@example.invalid'), findsOneWidget);
    expect(identical(router, container.read(appRouterProvider)), isTrue);
    verify(() => auth.hasStoredToken()).called(1);
  });

  testWidgets('system mode tracks device brightness while explicit mode stays fixed', (tester) async {
    final auth = AppearanceAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
    final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    addTearDown(container.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const TopCoffeeApp()));
    await tester.pumpAndSettle();
    Brightness current() => Theme.of(tester.element(find.byType(TextFormField).first)).brightness;
    expect(current(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(current(), Brightness.dark);
    await container.read(themePreferenceProvider.notifier).select(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(current(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(current(), Brightness.light);
    await container.read(themePreferenceProvider.notifier).select(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(current(), Brightness.dark);
  });
}
