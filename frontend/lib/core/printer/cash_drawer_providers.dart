import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/data/auth_repository.dart';
import '../branch/current_branch_provider.dart';
import '../offline/local_store.dart';
import 'cash_drawer_journal.dart';

final cashDrawerJournalProvider = Provider<CashDrawerJournal>((ref) {
  final journal = CashDrawerJournal(ref.watch(localStoreProvider));
  ref.onDispose(journal.dispose);
  return journal;
});

final cashDrawerScopeProvider = Provider<DrawerScope?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final branch = ref.watch(currentBranchProvider);
  if (auth is! AuthAuthenticated || branch == null ||
      !auth.user.hasPermission('orders.create') ||
      !(auth.user.hasPermission('branches.view-all') ||
        auth.user.branches.any((assigned) => assigned.id == branch.id))) {
    return null;
  }
  return (userId: auth.user.id, branchId: branch.id);
});

final cashDrawerSyncProvider = Provider<CashDrawerSync>((ref) {
  final api = ref.watch(apiClientProvider);
  return CashDrawerSync(
    ref.watch(cashDrawerJournalProvider),
    () => ref.read(cashDrawerScopeProvider),
    (event) async {
      final token = await api.readToken();
      if (token == null || ref.read(cashDrawerScopeProvider) != event.scope) {
        throw StateError('The original cashier and branch must be selected.');
      }
      // Pin the token; ApiClient must not substitute a newly signed-in cashier.
      await api.request((dio) => dio.post('/cash-drawer-events',
        data: event.toJson(),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ));
    },
  );
});

final cashDrawerSyncWorkerProvider = Provider<void>((ref) {
  if (ref.watch(cashDrawerScopeProvider) == null) return;
  final sync = ref.watch(cashDrawerSyncProvider);
  void run() {
    unawaited(sync.sync().catchError((Object _) {}));
  }
  run();
  final subscription = ref.watch(cashDrawerJournalProvider).changes.listen((_) => run());
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => run());
  ref.onDispose(() {
    timer.cancel();
    unawaited(subscription.cancel());
  });
});
