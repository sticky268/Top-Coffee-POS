import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branch/current_branch_provider.dart';
import '../offline/local_store.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/settings/data/receipt_settings.dart';
import 'print_queue.dart';
import 'printer_service.dart';

final printerServiceProvider = Provider<PrinterService>(
  (ref) => PrinterService(),
);
final printScopeProvider = Provider<PrintScope?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final branch = ref.watch(currentBranchProvider);
  return auth is AuthAuthenticated &&
          branch != null &&
          (auth.user.hasPermission('orders.view') ||
              auth.user.hasPermission('orders.create'))
      ? (userId: auth.user.id, branchId: branch.id)
      : null;
});
final printQueueProvider = Provider<PrintQueue>((ref) {
  final queue = PrintQueue(
    ref.watch(localStoreProvider),
    ref.watch(printerServiceProvider),
    () => ref.read(printScopeProvider),
    (job) async {
      final settings = await ReceiptSettings.load(
        branchKey: job.branchCode,
        branchNameFallback: job.branchName,
      );
      if (!settings.printerEnabled) {
        throw StateError(
          'Printing is disabled. Enable this branch’s printer in Receipt Settings.',
        );
      }
      return settings.printerIpAddress;
    },
  );
  ref.onDispose(queue.dispose);
  return queue;
});
final printJobsProvider = StreamProvider<List<PrintJob>>((ref) async* {
  final scope = ref.watch(printScopeProvider);
  if (scope == null) {
    yield [];
    return;
  }
  final queue = ref.watch(printQueueProvider);
  final events = StreamController<void>();
  final subscription = queue.changes.listen((_) => events.add(null));
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(events.close());
  });
  yield await queue.list(scope);
  await for (final _ in events.stream) {
    yield await queue.list(scope);
  }
});
final printQueueWorkerProvider = Provider<void>((ref) {
  final scope = ref.watch(printScopeProvider);
  if (scope == null) return;
  final queue = ref.watch(printQueueProvider);
  unawaited(queue.resumeWaiting(scope).catchError((Object _) {}));
});
