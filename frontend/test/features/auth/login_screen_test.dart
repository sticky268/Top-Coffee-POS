import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;
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

  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  setUp(() {
    repository = MockAuthRepository();
    when(() => repository.hasStoredToken()).thenAnswer((_) async => false);
  });

  /// Pumps LoginScreen with an explicit ProviderContainer (via
  /// UncontrolledProviderScope) so the test can deterministically await
  /// AuthController.initialization — rather than guessing how many
  /// `tester.pump()` calls are needed to flush the restoreSession() chain.
  Future<void> pumpLoginScreen(WidgetTester tester, {
    Size viewport = const Size(800, 600),
    bool dark = false,
    bool studio = false,
    double textScale = 1,
    double keyboardInset = 0,
    GlobalKey? preview,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: studio
              ? (dark ? CoffeeStudioTheme.dark : CoffeeStudioTheme.light)
              : (dark ? AppTheme.dark : AppTheme.light),
          home: const LoginScreen(),
          builder: (context, child) => RepaintBoundary(
            key: preview,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboardInset),
              ),
              child: child!,
            ),
          ),
        ),
      ),
    );

    // Building LoginScreen already triggered AuthController creation via
    // ref.watch(authControllerProvider) — .notifier here returns that same
    // instance, it does not create a second one.
    await container.read(authControllerProvider.notifier).initialization;
    await tester.runAsync(() => precacheImage(
        const AssetImage(LoginScreen.artworkAsset),
        tester.element(find.byType(LoginScreen))));
    await tester.pumpAndSettle();
  }

  Future<void> tapSignIn(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pump();
    await tester.tap(find.text('Sign in'));
  }

  testWidgets('shows validation errors when submitting an empty form', (tester) async {
    await pumpLoginScreen(tester);

    await tapSignIn(tester);
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
    await tapSignIn(tester);
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpLoginScreen(tester);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
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

    await tapSignIn(tester);
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('shows server cooldown message after HTTP 429 without signing in',
      (tester) async {
    const message =
        'Too many failed sign-in attempts. Try again in 15 minutes.';
    final options = RequestOptions(path: '/auth/login');
    final error = ApiExceptionMapper.fromDioException(DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: 429,
        data: {'message': message, 'code': 'LOGIN_LOCKED', 'retry_after': 900},
      ),
    ));
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        )).thenThrow(error);
    await pumpLoginScreen(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'cashier@topcoffee.test');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'wrongpass');
    await tapSignIn(tester);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        for (final studio in [false, true]) {
          testWidgets(
              'botanical login ${size.width}x${size.height} text $scale dark $dark studio $studio',
              (tester) async {
            final preview = GlobalKey();
            await pumpLoginScreen(tester,
                viewport: size,
                dark: dark,
                studio: studio,
                textScale: scale,
                preview: preview);
            expect(find.text('Top Coffee POS'), findsOneWidget);
            expect(find.text('Welcome back'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (!studio && scale == 1 &&
                (size.width == 390 || size.width == 1024)) {
              await savePreview(tester, preview,
                  'login-garden-${size.width}-${dark ? 'dark' : 'light'}');
            }
            final scrollable = find.descendant(
                of: find.byKey(const ValueKey('login-scroll')),
                matching: find.byType(Scrollable)).first;
            await tester.scrollUntilVisible(
                find.text('Sign in'), 160, scrollable: scrollable);
            await tester.pumpAndSettle();
            expect(find.text('Sign in').hitTestable(), findsOneWidget);
            await tester.ensureVisible(find.byTooltip('Show password'));
            await tester.pumpAndSettle();
            expect(find.byTooltip('Show password').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  testWidgets('large-text phone login keeps cooldown and submit usable above keyboard',
      (tester) async {
    const message =
        'Too many failed sign-in attempts. Try again in 15 minutes.';
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          deviceName: any(named: 'deviceName'),
        )).thenThrow(const UnknownApiException(message));
    await pumpLoginScreen(tester,
        viewport: const Size(390, 844),
        textScale: 2,
        keyboardInset: 300);
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Email'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'cashier@topcoffee.test');
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Password'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'wrongpass');
    await tapSignIn(tester);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await tester.ensureVisible(find.text(message));
    await tester.pumpAndSettle();
    expect(find.text(message).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
