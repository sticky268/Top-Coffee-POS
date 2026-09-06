import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/auth/application/auth_controller.dart';
import 'package:top_coffee_pos/features/auth/application/auth_state.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

const _testUser = AuthenticatedUser(
  id: 1,
  name: 'Cashier User',
  email: 'cashier@topcoffee.test',
  roles: ['cashier'],
  permissions: ['orders.create'],
  branches: [BranchSummary(id: 1, name: 'Riverside', code: 'PP-01')],
);

void main() {
  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
  });

  /// Builds a container AND forces AuthController into existence
  /// immediately, then awaits its own completion signal.
  ///
  /// Riverpod providers are lazy — a StateNotifierProvider isn't
  /// constructed until something reads it. The previous version of this
  /// test file called `Future<void>.delayed(Duration.zero)` *before* ever
  /// reading the provider, so the delay had nothing to wait for; the
  /// controller (and its constructor's restoreSession() call) was only
  /// created by the *following* `container.read(...)`, synchronously,
  /// right at the assertion. Reading `.notifier` here — before awaiting —
  /// is what actually starts restoration; awaiting `initialization`
  /// afterwards is what makes the wait meaningful.
  ({ProviderContainer container, AuthController controller}) buildAndStart() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);
    return (container: container, controller: controller);
  }

  group('session restoration (constructor)', () {
    test('goes to Unauthenticated when no token is stored', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => false);

      final built = buildAndStart();
      await built.controller.initialization;

      expect(built.container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('goes to Authenticated when a stored token is still valid', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => true);
      when(() => repository.getCurrentUser()).thenAnswer((_) async => _testUser);

      final built = buildAndStart();
      await built.controller.initialization;

      final state = built.container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'cashier@topcoffee.test');
    });

    test('clears the token and goes to Unauthenticated when the stored token is rejected', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => true);
      when(() => repository.getCurrentUser()).thenThrow(const AuthException());
      when(() => repository.clearStoredToken()).thenAnswer((_) async {});

      final built = buildAndStart();
      await built.controller.initialization;

      expect(built.container.read(authControllerProvider), isA<AuthUnauthenticated>());
      verify(() => repository.clearStoredToken()).called(1);
    });

    test('never gets stuck in Loading — falls back to Unauthenticated even on an unexpected error', () async {
      // Simulates e.g. a secure-storage/platform failure reading the token,
      // not just a typed ApiException from the network call.
      when(() => repository.hasStoredToken()).thenThrow(Exception('platform channel error'));
      when(() => repository.clearStoredToken()).thenAnswer((_) async {});

      final built = buildAndStart();
      await built.controller.initialization;

      final state = built.container.read(authControllerProvider);
      expect(state, isNot(isA<AuthLoading>()));
      expect(state, isA<AuthUnauthenticated>());
    });
  });

  group('login', () {
    test('sets Authenticated state on success', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => false);
      when(() => repository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            deviceName: any(named: 'deviceName'),
          )).thenAnswer((_) async => const LoginResult(token: 'abc123', user: _testUser));

      final built = buildAndStart();
      await built.controller.initialization; // let startup restoration land first

      await built.controller.login(
        email: 'cashier@topcoffee.test',
        password: 'password',
        deviceName: 'test-device',
      );

      final state = built.container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
    });

    test('sets Error state with the backend message on invalid credentials', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => false);
      when(() => repository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            deviceName: any(named: 'deviceName'),
          )).thenThrow(const AuthException('Invalid credentials'));

      final built = buildAndStart();
      await built.controller.initialization;

      await built.controller.login(
        email: 'cashier@topcoffee.test',
        password: 'wrong',
        deviceName: 'test-device',
      );

      final state = built.container.read(authControllerProvider);
      expect(state, isA<AuthError>());
      expect((state as AuthError).message, 'Invalid credentials');
    });
  });

  group('logout', () {
    test('sets Unauthenticated even if the repository call throws', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async => true);
      when(() => repository.getCurrentUser()).thenAnswer((_) async => _testUser);
      when(() => repository.logout()).thenThrow(const NetworkException());

      final built = buildAndStart();
      await built.controller.initialization;
      expect(built.container.read(authControllerProvider), isA<AuthAuthenticated>());

      await built.controller.logout();

      expect(built.container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });
  });

  group('disposal safety', () {
    test('does not throw when the container is disposed mid-restoration', () async {
      when(() => repository.hasStoredToken()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return true;
      });
      when(() => repository.getCurrentUser()).thenAnswer((_) async => _testUser);

      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      final controller = container.read(authControllerProvider.notifier);

      // Dispose while _restoreSession() is still awaiting hasStoredToken().
      container.dispose();

      // The pending restoreSession() future must resolve without throwing
      // (the `mounted` guards must stop it from touching `state` after
      // disposal) — this is the actual requirement behind "prevent
      // restoreSession() from updating state after disposal".
      await expectLater(controller.initialization, completes);
    });
  });
}
