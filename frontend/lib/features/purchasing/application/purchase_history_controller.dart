import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/purchase_repository.dart';
import '../domain/purchase_models.dart';

class PurchaseHistoryController
    extends AsyncNotifier<PurchaseHistoryPage> {
  int? _branchId;
  final int _perPage = 15;

  @override
  Future<PurchaseHistoryPage> build() async {
    return _loadPage(
      page: 1,
      branchId: _branchId,
    );
  }

  Future<PurchaseHistoryPage> _loadPage({
    required int page,
    int? branchId,
  }) {
    final repository = ref.read(purchaseRepositoryProvider);

    return repository.getPurchaseHistory(
      branchId: branchId,
      page: page,
      perPage: _perPage,
    );
  }

  Future<void> refresh({int? branchId}) async {
    _branchId = branchId;

    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return _loadPage(
        page: 1,
        branchId: _branchId,
      );
    });
  }

  Future<void> setBranch(int? branchId) async {
    if (_branchId == branchId) {
      return;
    }

    await refresh(branchId: branchId);
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;

    if (current == null || !current.hasNextPage) {
      return;
    }

    final nextPage = current.currentPage + 1;

    try {
      final next = await _loadPage(
        page: nextPage,
        branchId: _branchId,
      );

      state = AsyncData(
        PurchaseHistoryPage(
          purchases: [
            ...current.purchases,
            ...next.purchases,
          ],
          currentPage: next.currentPage,
          lastPage: next.lastPage,
          perPage: next.perPage,
          total: next.total,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final purchaseHistoryControllerProvider = AsyncNotifierProvider<
    PurchaseHistoryController,
    PurchaseHistoryPage>(
  PurchaseHistoryController.new,
);