import 'package:flutter/material.dart';
import 'package:top_coffee_pos/core/theme/coffee_studio_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_header.dart';

void main() {
  for (final studio in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'phone header fits long branches and switches studio=$studio text=$scale',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const first = BranchSummary(
            id: 21, name: 'Riverside Coffee Main Branch', code: 'PP-01');
        const second = BranchSummary(
            id: 22, name: 'BKK Coffee Second Branch', code: 'PP-02');
        const user = AuthenticatedUser(
          id: 16,
          name: 'Admin',
          email: 'admin@example.invalid',
          roles: ['admin'],
          permissions: ['branches.view-all'],
          branches: [first, second],
        );
        var loggedOut = false;
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
          child: MaterialApp(
              theme: studio ? CoffeeStudioTheme.light : null,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: Padding(
                padding: const EdgeInsets.all(16),
                child: DashboardHeader(
                    user: user, onLogout: () => loggedOut = true),
              )))),
        ));
        expect(tester.takeException(), isNull);
        final selector = find.byType(DropdownButton<BranchSummary?>);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find
            .text(studio ? second.name : '${second.name} (${second.code})')
            .last);
        await tester.pumpAndSettle();
        expect(container.read(currentBranchProvider)?.id, second.id);
        expect(find.byTooltip('Log out'), findsOneWidget);
        if (studio) {
          final identity = find.byKey(const ValueKey('studio-user-identity'));
          final name =
              find.descendant(of: identity, matching: find.text('Admin')).first;
          final role =
              find.descendant(of: identity, matching: find.text('Admin')).last;
          expect(tester.getTopLeft(role).dy,
              greaterThan(tester.getBottomLeft(name).dy));
          expect(find.byType(DropdownButtonHideUnderline), findsOneWidget);
          expect(find.byType(CircleAvatar), findsOneWidget);
        }
        await tester.ensureVisible(find.byTooltip('Log out'));
        await tester.tap(find.byTooltip('Log out'));
        expect(loggedOut, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
