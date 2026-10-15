import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/printer/cash_drawer_activity_screen.dart';
import 'package:top_coffee_pos/core/printer/cash_drawer_journal.dart';
import 'package:top_coffee_pos/core/printer/cash_drawer_providers.dart';

import '../../support/memory_local_store.dart';

void main() {
  const selected = (userId: 7, branchId: 8);
  testWidgets('scoped rejected records are visible and retry uploads audit evidence only', (tester) async {
    final journal = CashDrawerJournal(MemoryLocalStore());
    addTearDown(journal.dispose);
    final event = await journal.begin(selected, reason: 'Make change');
    await journal.flagForReview(event, 'Audit reference needs review.');
    await journal.begin((userId: 9, branchId: 8), reason: 'Private other-cashier reason');
    var uploads = 0;
    final sync = CashDrawerSync(journal, () => selected, (record) async {
      uploads++;
      expect(record.id, event.id);
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      cashDrawerScopeProvider.overrideWithValue(selected),
      cashDrawerJournalProvider.overrideWithValue(journal),
      cashDrawerSyncProvider.overrideWithValue(sync),
    ], child: const MaterialApp(home: CashDrawerActivityScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Audit upload needs review'), findsOneWidget);
    expect(find.text('Private other-cashier reason'), findsNothing);
    await tester.tap(find.text('Retry audit upload'));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(find.text('Audit saved to server'), findsOneWidget);
    expect(find.text('Retry audit upload'), findsNothing);
    expect(await journal.list(selected), hasLength(1));
  });

  testWidgets('without an authorized account and branch no local records are exposed', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      cashDrawerScopeProvider.overrideWithValue(null),
    ], child: const MaterialApp(home: CashDrawerActivityScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in and select an authorized branch'), findsOneWidget);
    expect(find.text('Retry audit upload'), findsNothing);
  });
}
