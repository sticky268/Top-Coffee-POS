import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/application/dashboard_controller.dart';
import 'package:top_coffee_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:top_coffee_pos/features/dashboard/domain/dashboard_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/dashboard_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockDashboardRepository extends Mock implements DashboardRepository {}

const _testUser = AuthenticatedUser(
  id: 1,
  name: 'Alex',
  email: 'cashier@topcoffee.test',
  roles: ['cashier'],
  permissions: ['orders.create'],
  branches: [BranchSummary(id: 1, name: 'Riverside', code: 'PP-01')],
);

const _stats = DashboardStats(
  todaysSales: 1248.50,
  todaysOrders: 86,
  averageOrderValue: 14.52,
  lowStockItemCount: 5,
);

final _orders = [
  RecentOrder(
    orderNumber: '#1042',
    time: DateTime.now().subtract(const Duration(minutes: 3)),
    customerOrTable: 'Table 4',
    itemCount: 3,
    total: 15.40,
    status: OrderStatus.preparing,
  ),
];

final _sales = [
  SalesDataPoint(date: DateTime.now(), total: 500),
];

void main() {
  group('DashboardScreen (isolated)', () {
    late MockAuthRepository authRepository;
    late MockDashboardRepository dashboardRepository;

    setUp(() {
      authRepository = MockAuthRepository();
      when(() => authRepository.hasStoredToken()).thenAnswer((_) async => true);
      when(() => authRepository.getCurrentUser())
          .thenAnswer((_) async => _testUser);
      dashboardRepository = MockDashboardRepository();
    });

    /// Pumps just DashboardScreen with explicit provider overrides, so we
    /// can deterministically await both controllers' `initialization`
    /// instead of guessing with pump counts.
    Future<ProviderContainer> pumpDashboard(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
          currentBranchProvider.overrideWith((ref) {
            final notifier = CurrentBranchNotifier(
              ref,
              listenToAuth: false,
            );
            notifier.selectBranch(_testUser.branches.first);
            return notifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      return container;
    }

    testWidgets('displays the four statistics once loaded', (tester) async {
      when(() => dashboardRepository.getStats())
          .thenAnswer((_) async => _stats);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      final container = await pumpDashboard(tester);
      await container.read(dashboardControllerProvider.notifier).initialization;
      await tester.pump();

      expect(find.text('\$1,248.50'), findsOneWidget); // Today's Sales
      expect(find.text('86'), findsOneWidget); // Today's Orders
      expect(find.text('\$14.52'), findsOneWidget); // Average Order
      expect(find.text('5 items'), findsOneWidget); // Low Stock
    });

    testWidgets('displays recent orders', (tester) async {
      when(() => dashboardRepository.getStats())
          .thenAnswer((_) async => _stats);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      final container = await pumpDashboard(tester);
      await container.read(dashboardControllerProvider.notifier).initialization;
      await tester.pump();

      expect(find.textContaining('#1042'), findsOneWidget);
      expect(find.text('Preparing'), findsOneWidget);
    });

    testWidgets('quick action buttons exist', (tester) async {
      when(() => dashboardRepository.getStats())
          .thenAnswer((_) async => _stats);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      final container = await pumpDashboard(tester);
      await container.read(dashboardControllerProvider.notifier).initialization;
      await tester.pump();

      expect(find.text('New Order'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets(
        'shows a loading indicator while data is in flight, then the content',
        (tester) async {
      final statsCompleter = Completer<DashboardStats>();
      when(() => dashboardRepository.getStats())
          .thenAnswer((_) => statsCompleter.future);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      await pumpDashboard(tester);
      await tester
          .pump(); // one frame — restoration/load kicked off but not resolved

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('New Order'), findsNothing);

      statsCompleter.complete(_stats);
      await tester.pumpAndSettle();

      expect(find.text('\$1,248.50'), findsOneWidget);
    });

    testWidgets('shows an error state with a working retry button',
        (tester) async {
      var callCount = 0;
      when(() => dashboardRepository.getStats()).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('network down');
        return _stats;
      });
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      final container = await pumpDashboard(tester);
      await container.read(dashboardControllerProvider.notifier).initialization;
      await tester.pump();

      expect(find.text('Could not load the dashboard'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('\$1,248.50'), findsOneWidget);
    });

    testWidgets('renders without overflow on a small phone-sized viewport',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => dashboardRepository.getStats())
          .thenAnswer((_) async => _stats);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      final container = await pumpDashboard(tester);
      await container.read(dashboardControllerProvider.notifier).initialization;
      await tester.pump();

      // A RenderFlex overflow (or any other render error) surfaces via
      // FlutterError, which tester.takeException() would capture.
      expect(tester.takeException(), isNull);
    });
  });

  group('DashboardScreen (full app + router)', () {
    testWidgets(
        'authenticated session reaches /home showing the dashboard, and logout returns to login',
        (tester) async {
      final authRepository = MockAuthRepository();
      when(() => authRepository.hasStoredToken()).thenAnswer((_) async => true);
      when(() => authRepository.getCurrentUser())
          .thenAnswer((_) async => _testUser);
      when(() => authRepository.logout()).thenAnswer((_) async {});

      final dashboardRepository = MockDashboardRepository();
      when(() => dashboardRepository.getStats())
          .thenAnswer((_) async => _stats);
      when(() => dashboardRepository.getRecentOrders())
          .thenAnswer((_) async => _orders);
      when(() => dashboardRepository.getSalesOverview())
          .thenAnswer((_) async => _sales);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderSyncWorkerProvider.overrideWith((ref) {}),
            authRepositoryProvider.overrideWithValue(authRepository),
            dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
          ],
          child: const TopCoffeeApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Landed on the dashboard, not stuck on splash or login.
      // The app shell and dashboard header both display the app name,
      // so use a dashboard-specific element to verify the destination.
      expect(find.text('New Order'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('New Order'), findsNothing);
    });

    testWidgets(
        'unauthenticated session is redirected to login, never reaching the dashboard',
        (tester) async {
      final authRepository = MockAuthRepository();
      when(() => authRepository.hasStoredToken())
          .thenAnswer((_) async => false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderSyncWorkerProvider.overrideWith((ref) {}),
            authRepositoryProvider.overrideWithValue(authRepository),
          ],
          child: const TopCoffeeApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('New Order'), findsNothing);
    });
  });
}
