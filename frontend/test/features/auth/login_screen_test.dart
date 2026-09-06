import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/auth/presentation/login_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
    when(() => repository.hasStoredToken()).thenAnswer((_) async => false);
  });

  /// Pumps LoginScreen with an explicit ProviderContainer (via
  /// UncontrolledProviderScope) so the test can deterministically await
  /// AuthController.initialization — rather than guessing how many
  /// `tester.pump()` calls are needed to flush the restoreSession() chain.
  Future<void> pumpLoginScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    // Building LoginScreen already triggered AuthController creation via
    // ref.watch(authControllerProvider) — .notifier here returns that same
    // instance, it does not create a second one.
    await container.read(authControllerProvider.notifier).initialization;
    await tester.pump();
  }

  testWidgets('shows validation errors when submitting an empty form', (tester) async {
    await pumpLoginScreen(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    verifyNever(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        ));
  });

  testWidgets('shows an error banner when login fails with invalid credentials', (tester) async {
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        )).thenThrow(const AuthException('Invalid credentials'));

    await pumpLoginScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'cashier@topcoffee.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrongpass');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpLoginScreen(tester);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('disables the submit button while a login is in flight', (tester) async {
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        )).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return const LoginResult(
        token: 'abc',
        user: AuthenticatedUser(
          id: 1,
          name: 'Cashier',
          email: 'cashier@topcoffee.test',
          roles: ['cashier'],
          permissions: [],
          branches: [],
        ),
      );
    });

    await pumpLoginScreen(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'cashier@topcoffee.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password123');

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
