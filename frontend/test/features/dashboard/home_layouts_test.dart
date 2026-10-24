import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/printer/print_queue_providers.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:top_coffee_pos/core/theme/home_layout_preference.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:top_coffee_pos/features/dashboard/application/dashboard_controller.dart';
import 'package:top_coffee_pos/features/dashboard/domain/dashboard_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/dashboard_screen.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/home_navigation_rail.dart';
import 'package:top_coffee_pos/features/settings/presentation/home_layout_settings_card.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class LayoutAuthRepository extends Mock implements AuthRepository {}

class LayoutDashboardRepository extends Mock implements DashboardRepository {}

const branch = BranchSummary(id: 21, name: 'Main Branch', code: 'MAIN');
const user = AuthenticatedUser(
    id: 16,
    name: 'Panha',
    email: 'preview@example.invalid',
    roles: [
      'manager'
    ],
    permissions: [
      'orders.create',
      'orders.view',
      'reports.view',
      'products.manage',
      'inventory.view',
      'customers.view',
      'settings.manage'
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

  Future<(ProviderContainer, LayoutDashboardRepository)> pumpHome(
      WidgetTester tester,
      HomeLayout layout,
      Size size,
      double scale,
      bool dark,
      {bool limited = false,
      bool studio = false,
      GlobalKey? preview}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = LayoutAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => limited
        ? const AuthenticatedUser(
            id: 16,
            name: 'Panha',
            email: 'preview@example.invalid',
            roles: ['manager'],
            permissions: ['reports.view'],
            branches: [branch])
        : user);
    final repo = LayoutDashboardRepository();
    when(() => repo.getStats()).thenAnswer((_) async => const DashboardStats(
        todaysSales: 428.50,
        todaysOrders: 47,
        averageOrderValue: 9.12,
        lowStockItemCount: 3));
    when(() => repo.getRecentOrders()).thenAnswer((_) async => [
          RecentOrder(
              orderNumber: '#002104',
              time: DateTime(2026, 10, 22, 10, 24),
              itemCount: 2,
              total: 18.50,
              status: OrderStatus.completed)
        ]);
    when(() => repo.getSalesOverview()).thenAnswer((_) async => [
          for (var day = 16; day <= 22; day++)
            SalesDataPoint(date: DateTime(2026, 10, day), total: day * 15.0)
        ]);
    final container = ProviderContainer(overrides: [
      initialHomeLayoutProvider.overrideWithValue(layout),
      authRepositoryProvider.overrideWithValue(auth),
      dashboardRepositoryProvider.overrideWithValue(repo),
      pendingOrdersProvider.overrideWith((ref) => Stream.value([])),
      printJobsProvider.overrideWith((ref) => Stream.value([])),
      orderSyncWorkerProvider.overrideWith((ref) {}),
      currentBranchProvider.overrideWith((ref) =>
          CurrentBranchNotifier(ref, listenToAuth: false)
            ..selectBranch(branch)),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/home', routes: [
      ShellRoute(
          builder: (context, state, child) =>
              AppShell(selectedRoute: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
            GoRoute(
                path: '/settings/home-layout',
                builder: (_, __) => const HomeLayoutSettingsScreen()),
            for (final path in [
              '/pos',
              '/operations',
              '/orders',
              '/customers',
              '/manage-menu',
              '/inventory',
              '/reports',
              '/settings/receipt',
              '/settings'
            ])
              GoRoute(
                  path: path,
                  builder: (_, __) => Scaffold(body: Text('Opened $path'))),
          ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
            theme: studio
                ? (dark ? CoffeeStudioTheme.dark : CoffeeStudioTheme.light)
                : (dark ? AppTheme.dark : AppTheme.light),
            routerConfig: router,
            builder: (context, child) => LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQueryData(
                        size: constraints.biggest,
                        textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: preview, child: child!),
                  ),
                ))));
    await tester.pumpAndSettle();
    return (container, repo);
  }

  for (final layout in HomeLayout.values) {
    for (final viewport in [
      (const Size(390, 844), 1.0, false),
      (const Size(1440, 1000), 1.0, false),
      (const Size(1024, 900), 1.0, true),
      (const Size(360, 800), 2.0, false),
    ]) {
      testWidgets('${layout.name} fits $viewport and opens the authorized menu',
          (tester) async {
        final preview = GlobalKey();
        await pumpHome(tester, layout, viewport.$1, viewport.$2, viewport.$3,
            preview: preview);
        expect(
            find.byKey(ValueKey('dashboard-${layout.name}')), findsOneWidget);
        expect(find.text('\$428.50'), findsOneWidget);
        expect(find.text('47'), findsOneWidget);
        expect(find.text('\$9.12'), findsOneWidget);
        expect(find.text('3 items'), findsOneWidget);
        if (layout == HomeLayout.modern && viewport.$1.width >= 900) {
          expect(tester.getSize(find.byType(HomeNavigationRail)).height,
              viewport.$1.height);
        }
        expect(find.textContaining('#002104'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await savePreview(tester, preview,
            'home-${layout.name}-${viewport.$1.width.toInt()}-${viewport.$2}-${viewport.$3}');
        final menu = find.text('Manage Menu').last;
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Opened /manage-menu'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final viewport in [
      (const Size(390, 844), 1.0, false),
      (const Size(1440, 1000), 1.0, false),
      (const Size(1024, 900), 1.0, true),
      (const Size(360, 800), 2.0, false),
    ]) {
      testWidgets('Coffee Studio ${layout.name} fits $viewport',
          (tester) async {
        final preview = GlobalKey();
        await pumpHome(tester, layout, viewport.$1, viewport.$2, viewport.$3,
            studio: true, preview: preview);
        expect(find.text('\$428.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await savePreview(tester, preview,
            'studio-home-${layout.name}-${viewport.$1.width.toInt()}-${viewport.$2}-${viewport.$3}');
      });
    }

    testWidgets('${layout.name} hides unauthorized tools', (tester) async {
      await pumpHome(tester, layout, const Size(390, 844), 1, false,
          limited: true);
      expect(find.text('Manage Menu'), findsNothing);
      expect(find.text('New Order'), findsNothing);
      expect(find.text('Inventory'), findsNothing);
      expect(find.text('Customers'), findsNothing);
      expect(find.text('Reports'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in [
    (const Size(390, 844), 1.0, false),
    (const Size(1024, 900), 1.0, true),
    (const Size(360, 800), 2.0, false),
  ]) {
    testWidgets('layout settings remain usable $viewport', (tester) async {
      await tester.binding.setSurfaceSize(viewport.$1);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final preview = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: viewport.$3 ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                  data: MediaQueryData(
                      size: viewport.$1,
                      textScaler: TextScaler.linear(viewport.$2)),
                  child: RepaintBoundary(
                      key: preview,
                      child: const HomeLayoutSettingsScreen())))));
      await tester.pumpAndSettle();
      for (final layout in HomeLayout.values) {
        final choice = find.byKey(ValueKey('home-layout-${layout.name}'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(container.read(homeLayoutProvider), layout);
        expect(await HomeLayoutStore().load(), layout);
        expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
      await savePreview(tester, preview,
          'home-settings-${viewport.$1.width.toInt()}-${viewport.$2}-${viewport.$3}');
    });
  }

  testWidgets('layout picker stays clear of device cutouts and gesture area',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    padding: EdgeInsets.only(left: 24, right: 16, bottom: 34)),
                child: HomeLayoutSettingsScreen()))));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(viewport.left, greaterThanOrEqualTo(24));
    expect(viewport.right, lessThanOrEqualTo(374));
    expect(viewport.bottom, lessThanOrEqualTo(810));
    expect(tester.takeException(), isNull);
  });

  testWidgets('modern full menu closes after opening a destination',
      (tester) async {
    await pumpHome(tester, HomeLayout.modern, const Size(1440, 1000), 1, false);
    await tester.tap(find.byTooltip('All tools'));
    await tester.pumpAndSettle();
    final destination = find.text('Daily Operations').last;
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();
    expect(find.text('Opened /operations'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets(
        'settings apply, persist and return home without reloading dashboard data $size',
        (tester) async {
      final (container, repo) =
          await pumpHome(tester, HomeLayout.classic, size, 1, false);
      for (final layout in [
        HomeLayout.modern,
        HomeLayout.coffeeCounter,
        HomeLayout.classic
      ]) {
        await tester.ensureVisible(find.byTooltip('Home layout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Home layout'));
        await tester.pumpAndSettle();
        final choice = find.byKey(ValueKey('home-layout-${layout.name}'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(container.read(homeLayoutProvider), layout);
        expect(await HomeLayoutStore().load(), layout);
        final context = tester.element(find.byType(HomeLayoutSettingsCard));
        GoRouter.of(context).pop();
        await tester.pumpAndSettle();
        expect(
            find.byKey(ValueKey('dashboard-${layout.name}')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      verify(() => repo.getStats()).called(1);
    });
  }

  testWidgets('each layout keeps its own scroll position without refetching',
      (tester) async {
    final (container, repo) = await pumpHome(
        tester, HomeLayout.classic, const Size(390, 844), 1, false);
    ScrollPosition position(HomeLayout layout) => tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byKey(PageStorageKey('home-scroll-${layout.name}')),
                matching: find.byType(Scrollable))
            .first)
        .position;
    position(HomeLayout.classic).jumpTo(240);
    await tester.pumpAndSettle();
    await container
        .read(homeLayoutPreferenceProvider.notifier)
        .select(HomeLayout.modern);
    await tester.pumpAndSettle();
    expect(position(HomeLayout.modern).pixels, 0);
    position(HomeLayout.modern).jumpTo(120);
    await tester.pumpAndSettle();
    await container
        .read(homeLayoutPreferenceProvider.notifier)
        .select(HomeLayout.coffeeCounter);
    await tester.pumpAndSettle();
    expect(position(HomeLayout.coffeeCounter).pixels, 0);
    await container
        .read(homeLayoutPreferenceProvider.notifier)
        .select(HomeLayout.classic);
    await tester.pumpAndSettle();
    expect(position(HomeLayout.classic).pixels, 240);
    expect(container.read(currentBranchProvider), branch);
    verify(() => repo.getStats()).called(1);
    expect(tester.takeException(), isNull);
  });

  for (final keyboard in [false, true]) {
    testWidgets('modern navigation label works with keyboard=$keyboard',
        (tester) async {
      await pumpHome(
          tester, HomeLayout.modern, const Size(1440, 1000), 1, false);
      final label = find.descendant(
          of: find.byType(HomeNavigationRail), matching: find.text('Reports'));
      if (keyboard) {
        Focus.of(tester.element(label)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(label);
      }
      await tester.pumpAndSettle();
      expect(find.text('Opened /reports'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open modern tools menu survives tablet-to-phone rotation',
      (tester) async {
    await pumpHome(tester, HomeLayout.modern, const Size(1440, 1000), 1, false);
    await tester.tap(find.byTooltip('All tools'));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    final destination = find.text('Daily Operations').last;
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();
    expect(find.text('Opened /operations'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout choices remain usable during an offline dashboard retry',
      (tester) async {
    final (container, repo) = await pumpHome(
        tester, HomeLayout.classic, const Size(390, 844), 1, false);
    when(() => repo.getStats())
        .thenAnswer((_) async => throw Exception('offline'));
    await container.read(dashboardControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Could not load the dashboard'), findsOneWidget);
    await container
        .read(homeLayoutPreferenceProvider.notifier)
        .select(HomeLayout.coffeeCounter);
    await tester.pumpAndSettle();
    expect(find.text('Could not load the dashboard'), findsOneWidget);
    expect(find.text('New Order'), findsNothing);
    when(() => repo.getStats()).thenAnswer((_) async => const DashboardStats(
        todaysSales: 428.50,
        todaysOrders: 47,
        averageOrderValue: 9.12,
        lowStockItemCount: 3));
    final retry = find.widgetWithText(FilledButton, 'Retry');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('dashboard-coffeeCounter')), findsOneWidget);
    expect(find.text('\$428.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
