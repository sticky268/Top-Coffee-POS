import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_repository.dart';
import 'staff_list_state.dart';

final staffListControllerProvider =
    StateNotifierProvider<StaffListController, StaffListState>((ref) {
  return StaffListController(ref.watch(staffRepositoryProvider));
});

class StaffListController extends StateNotifier<StaffListState> {
  StaffListController(this._repository)
      : super(const StaffListLoading()) {
    load();
  }

  final StaffRepository _repository;

  String _search = '';
  String? _role;
  int? _branchId;
  bool? _isActive;

  Future<void> load() async {
    state = const StaffListLoading();

    try {
      final page = await _repository.getStaff(
        search: _search.isEmpty ? null : _search,
        role: _role,
        branchId: _branchId,
        isActive: _isActive,
        page: 1,
      );

      if (!mounted) return;

      state = StaffListLoaded(
        staff: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;
      state = StaffListError(_messageFor(e));
    }
  }

  Future<void> refresh() async {
    try {
      final page = await _repository.getStaff(
        search: _search.isEmpty ? null : _search,
        role: _role,
        branchId: _branchId,
        isActive: _isActive,
        page: 1,
      );

      if (!mounted) return;

      state = StaffListLoaded(
        staff: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;
      state = StaffListError(_messageFor(e));
    }
  }

  Future<void> applySearch(String value) async {
    _search = value.trim();
    await load();
  }

  Future<void> setRole(String? role) async {
    _role = role;
    await load();
  }

  Future<void> setBranch(int? branchId) async {
    _branchId = branchId;
    await load();
  }

  Future<void> setActive(bool? isActive) async {
    _isActive = isActive;
    await load();
  }

  Future<void> clearFilters() async {
    _search = '';
    _role = null;
    _branchId = null;
    _isActive = null;
    await load();
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! StaffListLoaded ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = current.currentPage + 1;

      final page = await _repository.getStaff(
        search: _search.isEmpty ? null : _search,
        role: _role,
        branchId: _branchId,
        isActive: _isActive,
        page: nextPage,
      );

      if (!mounted) return;

      state = current.copyWith(
        staff: [...current.staff, ...page.data],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = current.copyWith(isLoadingMore: false);
    }
  }

  String _messageFor(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }

    return message;
  }
}
