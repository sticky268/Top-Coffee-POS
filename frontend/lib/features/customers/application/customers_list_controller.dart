import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/customers_repository.dart';
import 'customers_list_state.dart';

/// Loads and manages the customer list.
class CustomersListController extends StateNotifier<CustomersListState> {
  CustomersListController(this._repository, this._ref)
      : super(const CustomersListLoading()) {
    _branchId = _ref.read(currentBranchProvider)?.id;

    _ref.listen(
      currentBranchProvider,
      (_, next) {
        final nextBranchId = next?.id;

        if (_branchId == nextBranchId) {
          return;
        }

        _branchId = nextBranchId;
        refresh();
      },
    );

    _initialization = _load();
  }

  final CustomersRepository _repository;
  final Ref _ref;

  int? _branchId;
  String? _search;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> applySearch(String? search) {
    final value = search?.trim();

    _search = value == null || value.isEmpty ? null : value;

    return refresh();
  }

  Future<void> clearSearch() {
    _search = null;
    return refresh();
  }

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const CustomersListLoading();

    try {
      final page = await _repository.getCustomers(
        search: _search,
        branchId: _branchId,
        page: 1,
      );

      if (!mounted) return;

      state = CustomersListLoaded(
        customers: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;

      state = CustomersListError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! CustomersListLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = await _repository.getCustomers(
        search: _search,
        branchId: _branchId,
        page: current.currentPage + 1,
      );

      if (!mounted) return;

      final latest = state;

      if (latest is! CustomersListLoaded) return;

      state = latest.copyWith(
        customers: [...latest.customers, ...nextPage.data],
        currentPage: nextPage.currentPage,
        lastPage: nextPage.lastPage,
        total: nextPage.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;

      final latest = state;

      if (latest is CustomersListLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}

final customersListControllerProvider =
    StateNotifierProvider<CustomersListController, CustomersListState>((ref) {
  return CustomersListController(
    ref.watch(customersRepositoryProvider),
    ref,
  );
});
