import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_header.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';

class _Auth extends Mock implements AuthRepository {}

const _user = AuthenticatedUser(
  id: 1,
  name: 'Manager',
  email: 'manager@example.test',
  roles: ['manager'],
  permissions: ['orders.view', 'reports.view'],
  branches: [
    BranchSummary(id: 1, name: 'Riverside', code: 'PP-01'),
    BranchSummary(id: 2, name: 'BKK1', code: 'PP-02'),
  ],
);

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('branch switching stays on the dashboard at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
      when(() => auth.getCurrentUser()).thenAnswer((_) async => _user);
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pendingOrdersProvider.overrideWith((ref) => Stream.value([])),
        currentBranchProvider.overrideWith((ref) =>
            CurrentBranchNotifier(ref, listenToAuth: false)
              ..selectBranch(_user.branches.first)),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(initialLocation: '/home', routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(selectedRoute: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => Scaffold(
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  DashboardHeader(user: _user, onLogout: () {}),
                ]),
              ),
            ),
            GoRoute(
              path: '/orders',
              builder: (context, state) => Scaffold(
                appBar: const PageAppBar(title: Text('Orders')),
                body: const SizedBox.expand(key: ValueKey('orders-body')),
              ),
            ),
          ],
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      final selectors = find.byType(DropdownButton<BranchSummary?>);
      expect(selectors, findsOneWidget);
      await tester.tap(selectors);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BKK1 (PP-02)').last);
      await tester.pumpAndSettle();
      expect(container.read(currentBranchProvider)?.id, 2);

      router.go('/orders');
      await tester.pumpAndSettle();
      expect(selectors, findsNothing);
      expect(container.read(currentBranchProvider)?.id, 2);
      final contentTop =
          tester.getTopLeft(find.byKey(const ValueKey('orders-body'))).dy;
      expect(find.byType(AppBar), findsOneWidget);
      final expectedTop = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(contentTop, expectedTop);

      // Offline warnings remain available without a permanent branch row.
      container.read(cachedCatalogProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.textContaining('Using saved catalog.'), findsOneWidget);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(selectors, findsOneWidget);
      expect(tester.widget<DropdownButton<BranchSummary?>>(selectors).value?.id,
          2);
      expect(tester.takeException(), isNull);
    });
  }
}
