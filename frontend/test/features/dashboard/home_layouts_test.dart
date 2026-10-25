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
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_navigation.dart';
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

  for (final saved in ['classic', 'modern', 'coffeeCounter']) {
    testWidgets('legacy saved $saved cannot change the fixed home',
        (tester) async {
      SharedPreferences.setMockInitialValues({'appearance.home_layout': saved});
      final (_, repo) = await pumpHome(
          tester, HomeLayout.coffeeCounter, const Size(390, 844), 1, false);
      expect(find.byKey(const ValueKey('dashboard-coffeeCounter')),
          findsOneWidget);
      expect(find.byTooltip('Home layout'), findsNothing);
      verify(() => repo.getStats()).called(1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final layout in [HomeLayout.coffeeCounter]) {
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

  testWidgets('fixed home recovers during an offline dashboard retry',
      (tester) async {
    final (container, repo) = await pumpHome(
        tester, HomeLayout.classic, const Size(390, 844), 1, false);
    when(() => repo.getStats())
        .thenAnswer((_) async => throw Exception('offline'));
    await container.read(dashboardControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Could not load the dashboard'), findsOneWidget);
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
  for (final layout in [HomeLayout.coffeeCounter]) {
    testWidgets(
        'Studio ${layout.name} uses pinned navigation on landscape tablet',
        (tester) async {
      final preview = GlobalKey();
      await pumpHome(tester, layout, const Size(1280, 800), 1, false,
          studio: true, preview: preview);
      expect(find.byType(Drawer), findsNothing);
      expect(tester.getSize(find.byType(DashboardNavigation)).width, 108);
      final nav = find.byType(DashboardNavigation);
      final rows = <Rect>[];
      for (final label in [
        'Dashboard',
        'POS',
        'Orders',
        'Pending Orders',
        'Manage Menu'
      ]) {
        final text = find.descendant(of: nav, matching: find.text(label));
        final row =
            find.ancestor(of: text, matching: find.byType(InkWell)).first;
        rows.add(tester.getRect(row));
      }
      for (final row in rows.skip(1)) {
        expect(row.left, rows.first.left);
        expect(row.width, rows.first.width);
        expect(row.height, rows.first.height);
      }

      expect(
          find.byWidgetPredicate(
              (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
          findsNothing);
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview, 'studio-pinned-${layout.name}');
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('Studio phone drawer has full-width rows at text $scale',
        (tester) async {
      final preview = GlobalKey();
      await pumpHome(
          tester, HomeLayout.coffeeCounter, const Size(390, 844), scale, false,
          studio: true, preview: preview);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      final dashboard = find.descendant(
          of: drawer, matching: find.widgetWithText(ListTile, 'Dashboard'));
      expect(dashboard, findsOneWidget);
      expect(tester.getSize(dashboard).width, greaterThanOrEqualTo(250));
      final pos = find.descendant(
          of: drawer, matching: find.widgetWithText(ListTile, 'POS'));
      expect(
          tester
              .getRect(
                  find.descendant(of: dashboard, matching: find.byType(Icon)))
              .left,
          tester
              .getRect(find.descendant(of: pos, matching: find.byType(Icon)))
              .left);
      expect(
          tester
              .getRect(find.descendant(
                  of: dashboard, matching: find.text('Dashboard')))
              .left,
          tester
              .getRect(find.descendant(of: pos, matching: find.text('POS')))
              .left);

      expect(
          find.descendant(
              of: dashboard, matching: find.byIcon(Icons.dashboard)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview, 'studio-full-drawer-$scale');
      final menu =
          find.descendant(of: drawer, matching: find.text('Manage Menu'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Opened /manage-menu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Studio open drawer disappears cleanly after rotation to landscape',
      (tester) async {
    await pumpHome(
        tester, HomeLayout.coffeeCounter, const Size(390, 844), 1, false,
        studio: true);
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
        findsNothing);
    expect(tester.getSize(find.byType(DashboardNavigation)).width, 108);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
