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

  Future<void> pumpPosScreenWithEmptyStack(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/pos',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(
            body: Text('Dashboard Placeholder'),
          ),
        ),
        GoRoute(
          path: '/pos',
          builder: (context, state) => const PosScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          posRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pump();
  }

  testWidgets(
    'shows an explicit back arrow even when /pos is the root of the stack',
    (tester) async {
      await pumpPosScreenWithEmptyStack(tester);

      expect(
        find.byTooltip('Back to Dashboard'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping the back arrow navigates to /home',
    (tester) async {
      await pumpPosScreenWithEmptyStack(tester);

      await tester.tap(
        find.byTooltip('Back to Dashboard'),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Dashboard Placeholder'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PopScope intercepts system back and navigates to /home',
    (tester) async {
      await pumpPosScreenWithEmptyStack(tester);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(
        find.text('Dashboard Placeholder'),
        findsOneWidget,
      );
    },
  );
}
