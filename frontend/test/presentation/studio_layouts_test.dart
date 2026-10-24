import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:top_coffee_pos/core/widgets/studio_layout.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/menu/presentation/manage_menu_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/reports_home_screen.dart';
import 'package:top_coffee_pos/features/settings/presentation/settings_screen.dart';
import 'ui_polish_test.dart' show savePreview;

class _Auth extends Mock implements AuthRepository {}

const branch = BranchSummary(id: 1, name: 'Riverside', code: 'RIVER');
const user = AuthenticatedUser(
    id: 1,
    name: 'Panha',
    email: 'preview@example.invalid',
    roles: [
      'manager'
    ],
    permissions: [
      'products.manage',
      'reports.view',
      'orders.create',
      'orders.view',
      'settings.manage',
      'customers.manage',
      'inventory.view',
      'expenses.manage'
    ],
    branches: [
      branch
    ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  for (final viewport in [
    (const Size(1280, 900), 1.0, false),
    (const Size(390, 844), 1.0, false),
    (const Size(390, 844), 2.0, true),
  ]) {
    for (final page in [
      ('menu', '/manage-menu', const ManageMenuScreen()),
      ('reports', '/reports', const ReportsHomeScreen()),
      ('settings', '/settings', const SettingsScreen()),
    ]) {
      testWidgets('Studio ${page.$1} layout $viewport', (tester) async {
        await tester.binding.setSurfaceSize(viewport.$1);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final auth = _Auth();
        when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
        when(() => auth.getCurrentUser()).thenAnswer((_) async => user);
        final container = ProviderContainer(overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          currentBranchProvider.overrideWith((ref) =>
              CurrentBranchNotifier(ref, listenToAuth: false)
                ..selectBranch(branch)),
        ]);
        addTearDown(container.dispose);
        await container.read(authControllerProvider.notifier).initialization;
        final preview = GlobalKey();
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme:
                viewport.$3 ? CoffeeStudioTheme.dark : CoffeeStudioTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    size: viewport.$1,
                    textScaler: TextScaler.linear(viewport.$2)),
                child: RepaintBoundary(key: preview, child: child!)),
            home: AppShell(selectedRoute: page.$2, child: page.$3),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (viewport.$1.width >= 900) {
          expect(find.text('Panha'), findsOneWidget);
        }
        if (page.$1 == 'menu' || page.$1 == 'reports') {
          expect(find.byType(StudioActionBoard), findsWidgets);
        }
        if (page.$1 == 'settings') {
          await tester.tap(find.text('App theme'));
          await tester.pumpAndSettle();
          expect(find.text('Original'), findsOneWidget);
          expect(find.text('Coffee Studio'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await savePreview(tester, preview,
            'studio-layout-${page.$1}-${viewport.$1.width.toInt()}-${viewport.$2}');
      });
    }
  }
}
