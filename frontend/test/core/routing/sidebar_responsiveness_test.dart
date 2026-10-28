import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/routing/app_router.dart';
import 'package:top_coffee_pos/core/routing/sidebar_route.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_navigation.dart';

class _Auth extends Mock implements AuthRepository {}

const _destinations = {
  'Dashboard': '/home',
  'POS': '/pos/select-table',
  'Orders': '/orders',
  'Pending Orders': '/pending-orders',
  'Manage Menu': '/manage-menu',
  'Daily Operations': '/operations',
  'Print Queue': '/print-queue',
  'Inventory': '/inventory',
  'Tables': '/tables',
  'Expenses': '/expenses',
  'Suppliers': '/suppliers',
  'Purchases': '/purchases',
  'Customers': '/customers',
  'Loyalty': '/loyalty',
  'Reports': '/reports',
  'Staff & Permissions': '/staff',
  'Audit Log': '/audit-log',
  'Branches': '/branches',
  'Settings': '/settings',
};

Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  required double width,
  bool studio = false,
  void Function(String)? onLoad,
  Future<void>? slowRequest,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = _Auth();
  when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
  final router = GoRouter(initialLocation: '/orders', routes: [
    ShellRoute(
      builder: (_, state, child) =>
          AppShell(selectedRoute: state.uri.path, child: child),
      routes: [
        for (final path in _destinations.values)
          SidebarRoute(
              path: path,
              builder: (_, __) => _Destination(
                    path: path,
                    onLoad: onLoad,
                    request: path == '/inventory' ? slowRequest : null,
                  )),
        GoRoute(
            path: '/orders/detail',
            builder: (_, __) => const Scaffold(body: Text('Order detail'))),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp.router(
      theme: studio ? CoffeeStudioTheme.light : AppTheme.light,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openMenu(WidgetTester tester) async {
  final shell = tester.state<ScaffoldState>(find.byType(Scaffold).first);
  if (shell.widget.drawer != null) {
    shell.openDrawer();
    await tester.pumpAndSettle();
  }
}

Future<void> _tapDestination(WidgetTester tester, String label) async {
  final navigation = find.byType(DashboardNavigation).hitTestable();
  final scrollable =
      find.descendant(of: navigation, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(label), 250,
      scrollable: scrollable);
  await tester.pump();
  await tester.tap(find.text(label).first);
}

void main() {
  test('real router uses immediate pages for every sidebar destination', () {
    final auth = _Auth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    final shell = router.configuration.routes.whereType<ShellRoute>().single;
    for (final path in _destinations.values) {
      expect(
          shell.routes
              .whereType<GoRoute>()
              .singleWhere((route) => route.path == path),
          isA<SidebarRoute>(),
          reason: path);
    }
    expect(
        shell.routes
            .whereType<GoRoute>()
            .singleWhere((route) => route.path == '/orders/:id'),
        isNot(isA<SidebarRoute>()));
  });

  for (final studio in [false, true]) {
    for (final width in [390.0, 1200.0]) {
      testWidgets(
          'all sidebar destinations respond: studio=$studio width=$width',
          (tester) async {
        final router = await _pumpShell(tester, width: width, studio: studio);
        for (final entry in _destinations.entries) {
          await _openMenu(tester);
          await _tapDestination(tester, entry.key);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, entry.value);
          expect(find.text('Destination: ${entry.value}'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('destination starts only after the drawer finishes closing',
      (tester) async {
    final loads = <String>[];
    final router = await _pumpShell(tester, width: 390, onLoad: loads.add);
    await _openMenu(tester);
    await _tapDestination(tester, 'POS');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(router.routeInformationProvider.value.uri.path, '/orders');
    expect(loads, ['/orders']);
    await tester.pumpAndSettle();
    expect(loads, ['/orders', '/pos/select-table']);
    expect(find.byType(Drawer).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid drawer selections open only the latest destination',
      (tester) async {
    final loads = <String>[];
    final router = await _pumpShell(tester, width: 390, onLoad: loads.add);
    await _openMenu(tester);
    await tester.tap(find.text('Dashboard').first);
    await tester.tap(find.text('POS').first);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/pos/select-table');
    expect(loads, ['/orders', '/pos/select-table']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external navigation cancels a pending drawer selection',
      (tester) async {
    final loads = <String>[];
    final router = await _pumpShell(tester, width: 390, onLoad: loads.add);
    await _openMenu(tester);
    await tester.tap(find.text('POS').first);
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(loads, isNot(contains('/pos/select-table')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting the current section closes drawer without reload',
      (tester) async {
    final loads = <String>[];
    await _pumpShell(tester, width: 390, onLoad: loads.add);
    await _openMenu(tester);
    await _tapDestination(tester, 'Orders');
    await tester.pumpAndSettle();
    expect(loads, ['/orders']);
    expect(find.byType(Drawer).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar stays usable while a destination request is pending',
      (tester) async {
    final slow = Completer<void>();
    final router =
        await _pumpShell(tester, width: 390, slowRequest: slow.future);
    await _openMenu(tester);
    await _tapDestination(tester, 'Inventory');
    // A progress indicator intentionally keeps animating; do not pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/inventory');
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _tapDestination(tester, 'POS');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/pos/select-table');
    slow.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned sidebar changes page without a route animation',
      (tester) async {
    final router = await _pumpShell(tester, width: 1200, studio: true);
    await _tapDestination(tester, 'POS');
    await tester.pump();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/pos/select-table');
    final element = tester.element(find.text('Destination: /pos/select-table'));
    expect(ModalRoute.of(element)!.animation!.value, 1);
    expect(ModalRoute.of(element)!.animation!.isCompleted, isTrue);
  });

  testWidgets('detail pages retain normal push and back navigation',
      (tester) async {
    final router = await _pumpShell(tester, width: 1200, studio: true);
    unawaited(router.push<void>('/orders/detail'));
    await tester.pumpAndSettle();
    expect(find.text('Order detail'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Destination: /orders'), findsOneWidget);
  });
}

class _Destination extends StatefulWidget {
  const _Destination({required this.path, this.onLoad, this.request});
  final String path;
  final void Function(String)? onLoad;
  final Future<void>? request;
  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination> {
  @override
  void initState() {
    super.initState();
    widget.onLoad?.call(widget.path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Workspace')),
        body: widget.request == null
            ? Text('Destination: ${widget.path}')
            : FutureBuilder<void>(
                future: widget.request,
                builder: (_, snapshot) =>
                    snapshot.connectionState == ConnectionState.done
                        ? const Text('Loaded')
                        : const CircularProgressIndicator()),
      );
}
