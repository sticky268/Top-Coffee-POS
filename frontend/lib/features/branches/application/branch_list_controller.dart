import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/branch_repository.dart';
import 'branch_list_state.dart';

final branchListControllerProvider =
    StateNotifierProvider<BranchListController, BranchListState>((ref) {
  return BranchListController(ref.watch(branchRepositoryProvider));
});

class BranchListController extends StateNotifier<BranchListState> {
  BranchListController(this._repository)
      : super(const BranchListLoading()) {
    _initialization = _load();
  }

  final BranchRepository _repository;

  String _search = '';
  bool? _isActive;
  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  Future<void> load() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const BranchListLoading();

    try {
      final page = await _repository.getBranches(
        search: _search.isEmpty ? null : _search,
        isActive: _isActive,
        page: 1,
      );

      if (!mounted) return;

      state = BranchListLoaded(
        branches: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;

      state = BranchListError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  Future<void> applySearch(String value) {
    _search = value.trim();
    return refresh();
  }

  Future<void> setActive(bool? isActive) {
    _isActive = isActive;
    return refresh();
  }

  Future<void> clearFilters() {
    _search = '';
    _isActive = null;
    return refresh();
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! BranchListLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = current.copyWith(isLoadingMore: true);

    try {
      final page = await _repository.getBranches(
        search: _search.isEmpty ? null : _search,
        isActive: _isActive,
        page: current.currentPage + 1,
      );

      if (!mounted) return;

      final latest = state;

      if (latest is! BranchListLoaded) return;

      state = latest.copyWith(
        branches: [...latest.branches, ...page.data],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;

      final latest = state;

      if (latest is BranchListLoaded) {
        state = latest.copyWith(isLoadingMore: false);
      }
    }
  }
}
