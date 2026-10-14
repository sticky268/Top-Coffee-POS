import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/domain/order_models.dart';
import '../../features/orders/domain/orders_list_filters.dart';
import '../branch/current_branch_provider.dart';

final lastCompletedOrderProvider =
    FutureProvider.autoDispose<OrderSummary?>((ref) async {
  final branch = ref.watch(currentBranchProvider);
  if (branch == null) {
    return null;
  }

  final page = await ref.read(ordersRepositoryProvider).getOrders(
        page: 1,
        branchId: branch.id,
        filters: const OrdersListFilters(status: 'completed'),
      );

  return page.orders.isEmpty ? null : page.orders.first;
});
