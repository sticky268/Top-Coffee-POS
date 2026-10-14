import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/pos/domain/pos_models.dart';
import '../branch/current_branch_provider.dart';
import '../network/api_client.dart';
import '../network/api_exceptions.dart';
import 'order_outbox.dart';

typedef OrderScope = ({int userId, int branchId});

class OrderSync {
  OrderSync(this.outbox, this.api, this.scope);
  final OrderOutbox outbox;
  final ApiClient api;
  final OrderScope? Function() scope;
  Future<void>? _running;

  Future<void> sync() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    final selected = scope();
    if (selected == null) return;
    final orders = await outbox.list(selected.userId, selected.branchId);
    for (final order in orders) {
      if (scope() != selected) return;
      if (order.status != 'pending') continue;
      var stop = false;
      await outbox.withRequestLock(order.uuid, () async {
        if (scope() != selected) {
          stop = true;
          return;
        }
        final current = await outbox.list(selected.userId, selected.branchId);
        if (!current.any(
            (item) => item.uuid == order.uuid && item.status == 'pending')) {
          return;
        }
        if (scope() != selected) {
          stop = true;
          return;
        }
        try {
          final response = await api
              .request((dio) => dio.post(order.endpoint, data: order.payload));
          final confirmation = OrderConfirmation.fromJson(
              response.data['data'] as Map<String, dynamic>);
          await outbox.finish(order, orderId: confirmation.orderId);
        } catch (error) {
          await outbox.finish(order, error: error);
          stop = error is NetworkException ||
              error is ServerException ||
              error is AuthException ||
              error is SubscriptionException;
        }
      });
      if (stop) return;
    }
  }
}

final orderScopeProvider = Provider<OrderScope?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final branch = ref.watch(currentBranchProvider);
  return auth is AuthAuthenticated && branch != null
      ? (userId: auth.user.id, branchId: branch.id)
      : null;
});

final orderSyncProvider = Provider<OrderSync>((ref) => OrderSync(
      ref.watch(orderOutboxProvider),
      ref.watch(apiClientProvider),
      () => ref.read(orderScopeProvider),
    ));

final pendingOrdersProvider = StreamProvider<List<PendingOrder>>((ref) async* {
  final scope = ref.watch(orderScopeProvider);
  if (scope == null) {
    yield [];
    return;
  }
  final outbox = ref.watch(orderOutboxProvider);
  // Subscribe before the initial read so a concurrent save is never missed.
  final controller = StreamController<void>();
  final subscription = outbox.changes.listen((_) => controller.add(null));
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  yield await outbox.list(scope.userId, scope.branchId);
  await for (final _ in controller.stream) {
    yield await outbox.list(scope.userId, scope.branchId);
  }
});

/// Runs only while an authenticated app is open. No hidden OS background job.
final orderSyncWorkerProvider = Provider<void>((ref) {
  final scope = ref.watch(orderScopeProvider);
  if (scope == null) return;
  final sync = ref.watch(orderSyncProvider);
  void run() {
    unawaited(sync.sync().catchError((Object _) {}));
  }

  run();
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => run());
  ref.onDispose(timer.cancel);
});
