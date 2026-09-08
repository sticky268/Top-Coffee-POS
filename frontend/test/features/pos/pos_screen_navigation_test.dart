import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/presentation/pos_screen.dart';

class MockPosRepository extends Mock implements PosRepository {}

void main() {
  late MockPosRepository repository;

  setUp(() {
    repository = MockPosRepository();
    when(() => repository.getCategories()).thenAnswer((_) async => []);
    when(() => repository.getProducts()).thenAnswer((_) async => []);
  });

  /// Pumps PosScreen behind a minimal real GoRouter with `/pos` as the
  /// *initial* (and therefore only) location — this reproduces the exact
  /// bug scenario: reaching /pos via context.go() (as the post-checkout
  /// "New Order" button does) replaces the stack, so there is nothing to
  /// pop. A '/home' route renders a simple placeholder so the test can
  /// assert navigation landed there without needing the real Dashboard's
  /// providers.
  Future<void> pumpPosScreenWithEmptyStack(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/pos',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('Dashboard Placeholder'))),
        GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [posRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows an explicit back arrow even when /pos is the root of the stack', (tester) async {
    await pumpPosScreenWithEmptyStack(tester);

    // This is the actual bug: /pos reached via context.go() (stack
    // replaced, nothing to pop) previously showed no back button at all,
    // since Flutter's automatic AppBar back button only appears when
    // Navigator.canPop() is true.
    expect(find.byTooltip('Back to Dashboard'), findsOneWidget);
  });

  testWidgets('tapping the back arrow navigates to /home', (tester) async {
    await pumpPosScreenWithEmptyStack(tester);

    await tester.tap(find.byTooltip('Back to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard Placeholder'), findsOneWidget);
  });

  testWidgets('a system-level pop attempt (Android back button/gesture) also navigates to /home', (tester) async {
    await pumpPosScreenWithEmptyStack(tester);

    // Navigator.maybePop() is the actual mechanism the Android system
    // back button and back gesture invoke — it's what PopScope
    // intercepts. This is deliberately NOT the same path as the AppBar
    // button test above: that IconButton calls context.go('/home')
    // directly on tap, bypassing PopScope entirely. This test instead
    // triggers a pop attempt the way the OS does, and verifies PopScope's
    // canPop: false + onPopInvokedWithResult redirect actually fires —
    // testing the real behavior rather than introspecting the widget tree
    // for a PopScope instance.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Dashboard Placeholder'), findsOneWidget);
  });
}
