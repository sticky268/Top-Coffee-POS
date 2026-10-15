import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/pos/domain/pos_models.dart';
import '../../features/settings/data/receipt_settings.dart';
import '../branch/current_branch_provider.dart';
import 'print_queue.dart';
import 'print_queue_providers.dart';

const cashDrawerFailureMessage =
    'Payment completed. Drawer command could not be confirmed. Check the drawer before using Open cash drawer.';

/// Consumes one device-local automatic attempt for each confirmed cash sale.
/// No receipt reads, reprints or background sync call this service.
class CashSaleDrawer {
  CashSaleDrawer(this.queue, this.scope, this.destination);
  final PrintQueue queue;
  final PrintScope? Function() scope;
  final Future<String> Function(PrintScope selected) destination;

  Future<String?> afterPayment(
    OrderConfirmation confirmation, int? userId, int? branchId,
  ) async {
    if (!confirmation.hasCompletedCashPayment) return null;
    try {
      final selected = scope();
      if (selected == null || selected.userId != userId || selected.branchId != branchId) {
        throw StateError('The original cashier and branch must still be selected.');
      }
      await queue.openCashDrawer(selected, () => destination(selected), () {
        if (scope() != selected) throw StateError('Cashier, permission or branch changed.');
      }, completedSaleId: confirmation.orderId);
      return null;
    } catch (_) {
      return cashDrawerFailureMessage;
    }
  }
}

final cashSaleDrawerProvider = Provider<CashSaleDrawer>((ref) {
  return CashSaleDrawer(ref.watch(printQueueProvider), () {
    final auth = ref.read(authControllerProvider);
    final branch = ref.read(currentBranchProvider);
    if (auth is! AuthAuthenticated || branch == null ||
        !auth.user.hasPermission('orders.create') ||
        !(auth.user.hasPermission('branches.view-all') ||
          auth.user.branches.any((b) => b.id == branch.id))) {
      return null;
    }
    return (userId: auth.user.id, branchId: branch.id);
  }, (selected) async {
    final branch = ref.read(currentBranchProvider);
    if (branch == null || branch.id != selected.branchId) throw StateError('Branch changed.');
    final settings = await ReceiptSettings.load(
      branchKey: branch.code, branchNameFallback: branch.name);
    if (!settings.printerEnabled) throw StateError('Enable the branch printer in Receipt Settings.');
    return settings.printerIpAddress;
  });
});
