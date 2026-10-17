import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/features/operations/presentation/operations_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Operations extends Mock implements OperationsRepository {}

void main() {
  testWidgets('a historical shift view can return to the active shift list',
      (tester) async {
    const user = AuthenticatedUser(
      id: 1,
      name: 'Manager',
      email: 'manager@example.test',
      roles: ['manager'],
      permissions: ['orders.create', 'reports.view'],
      branches: [BranchSummary(id: 2, name: 'Cafe', code: 'PP-02')],
    );
    final auth = _Auth();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => user);
    final operations = _Operations();
    when(() => operations.pending()).thenAnswer((_) async => []);
    final requests = <Map<String, dynamic>>[];
    when(() => operations.get('/shifts', query: any(named: 'query')))
        .thenAnswer((call) async {
      final query = call.namedArguments[#query] as Map<String, dynamic>;
      requests.add(Map.of(query));
      final historical = query['shift_id'] != null;
      return [
        {
          'id': historical ? 5 : 12,
          'user_id': 1,
          'cashier_name': 'Manager',
          'status': historical ? 'closed' : 'open',
          'live_expected_cash': 20,
          'difference': 0,
          'reviewed_at': '2026-10-17T00:00:00Z',
        },
      ];
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        operationsRepositoryProvider.overrideWithValue(operations),
        currentBranchProvider.overrideWith((ref) =>
            CurrentBranchNotifier(ref, listenToAuth: false)
              ..selectBranch(user.branches.first)),
        pendingOrdersProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: const MaterialApp(
        home: OperationsScreen(initialShiftId: 5),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Show all shifts'), findsOneWidget);
    expect(find.text('Open shift'), findsNothing);
    expect(requests, [
      {'shift_id': 5}
    ]);

    await tester.tap(find.text('Show all shifts'));
    await tester.pumpAndSettle();

    expect(requests.last, isEmpty);
    expect(find.text('Show all shifts'), findsNothing);
    expect(find.text('Open shift'), findsNothing);
    expect(find.textContaining('Shift #12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
