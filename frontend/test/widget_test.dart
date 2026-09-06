import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';

// The real AuthRepository goes through ApiClient -> flutter_secure_storage,
// which uses a platform MethodChannel that isn't available in a plain
// `flutter test` widget environment. AuthController now calls
// hasStoredToken() on startup (Phase 3), so this test overrides the
// repository with a mock instead of hitting the real plugin.
class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('App boots to splash screen without crashing', (tester) async {
    final repository = MockAuthRepository();
    when(() => repository.hasStoredToken()).thenAnswer((_) async => false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const TopCoffeeApp(),
      ),
    );
    await tester.pump();

    // Before restoreSession()'s Future resolves, the router holds on the
    // splash screen (AuthInitial/AuthLoading) — same assertion as Phase 1.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
