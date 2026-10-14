import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_header.dart';

void main() {
  testWidgets('phone header fits long branch names and can switch branches', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const first = BranchSummary(id: 21, name: 'Riverside Coffee Main Branch', code: 'PP-01');
    const second = BranchSummary(id: 22, name: 'BKK Coffee Second Branch', code: 'PP-02');
    const user = AuthenticatedUser(
      id: 16, name: 'Admin', email: 'admin@example.invalid',
      roles: ['admin'], permissions: ['branches.view-all'],
      branches: [first, second],
    );
    final container = ProviderContainer(overrides: [
      currentBranchProvider.overrideWith((ref) {
        final notifier = CurrentBranchNotifier(ref, listenToAuth: false);
        notifier.selectBranch(first);
        return notifier;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: DashboardHeader(user: user, onLogout: () {}),
      ))),
    ));
    expect(tester.takeException(), isNull);
    final selector = find.byType(DropdownButton<BranchSummary?>);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${second.name} (${second.code})').last);
    await tester.pumpAndSettle();
    expect(container.read(currentBranchProvider)?.id, second.id);
    expect(find.byTooltip('Log out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
