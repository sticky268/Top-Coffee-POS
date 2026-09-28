import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audit_log_repository.dart';

import 'audit_log_list_state.dart';

final auditLogListControllerProvider =
    StateNotifierProvider<AuditLogListController, AuditLogListState>((ref) {
  return AuditLogListController(ref.watch(auditLogRepositoryProvider));
});

class AuditLogListController extends StateNotifier<AuditLogListState> {
  AuditLogListController(this._repository)
      : super(const AuditLogListLoading()) {
    load();
  }

  final AuditLogRepository _repository;

  String _search = '';
  String? _action;
  int? _userId;
  String? _auditableType;
  DateTime? _from;
  DateTime? _to;

  Future<void> load() async {
    state = const AuditLogListLoading();

    try {
      final page = await _repository.getAuditLogs(
        search: _search.isEmpty ? null : _search,
        action: _action,
        userId: _userId,
        auditableType: _auditableType,
        from: _from,
        to: _to,
        page: 1,
      );

      if (!mounted) return;

      state = AuditLogListLoaded(
        logs: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;
      state = AuditLogListError(_messageFor(e));
    }
  }

  Future<void> refresh() async {
    try {
      final page = await _repository.getAuditLogs(
        search: _search.isEmpty ? null : _search,
        action: _action,
        userId: _userId,
        auditableType: _auditableType,
        from: _from,
        to: _to,
        page: 1,
      );

      if (!mounted) return;

      state = AuditLogListLoaded(
        logs: page.data,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } catch (e) {
      if (!mounted) return;
      state = AuditLogListError(_messageFor(e));
    }
  }

  Future<void> applySearch(String value) async {
    _search = value.trim();
    await load();
  }

  Future<void> setAction(String? action) async {
    _action = action;
    await load();
  }

  Future<void> setUser(int? userId) async {
    _userId = userId;
    await load();
  }

  Future<void> setAuditableType(String? auditableType) async {
    _auditableType = auditableType;
    await load();
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    _from = from;
    _to = to;
    await load();
  }

  Future<void> clearFilters() async {
    _search = '';
    _action = null;
    _userId = null;
    _auditableType = null;
    _from = null;
    _to = null;
    await load();
  }

  Future<void> loadMore() async {
    final current = state;

    if (current is! AuditLogListLoaded ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }

    state = current.copyWith(isLoadingMore: true);

    try {
      final nextPage = current.currentPage + 1;

      final page = await _repository.getAuditLogs(
        search: _search.isEmpty ? null : _search,
        action: _action,
        userId: _userId,
        auditableType: _auditableType,
        from: _from,
        to: _to,
        page: nextPage,
      );

      if (!mounted) return;

      state = current.copyWith(
        logs: [...current.logs, ...page.data],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoadingMore: false,
      );
    } catch (_) {
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