import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/home_layout_preference.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/features/operations/presentation/cashier_workspace.dart';

void main() {
  for (final layout in [HomeLayout.coffeeCounter]) {
    testWidgets(
      '${layout.name} cashier sees selling and shift actions without owner sales metrics',
      (tester) async {
        const user = AuthenticatedUser(
          id: 1,
          name: 'Cashier',
          email: 'ci@example.invalid',
          roles: ['cashier'],
          permissions: ['orders.create', 'orders.view'],
          branches: [BranchSummary(id: 1, name: 'Cafe', code: 'CA-01')],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentBranchProvider.overrideWith(
                (ref) => CurrentBranchNotifier(ref, listenToAuth: false)
                  ..selectBranch(user.branches.first),
              ),
              shiftsProvider.overrideWith((ref) async => []),
              pendingOrdersProvider.overrideWith((ref) => Stream.value([])),
            ],
            child: const MaterialApp(home: CashierWorkspace(user: user)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cashier workspace'), findsOneWidget);
        expect(find.text('Open your shift'), findsOneWidget);
        expect(find.text('New takeaway order'), findsOneWidget);
        expect(find.text("Today's Sales"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
