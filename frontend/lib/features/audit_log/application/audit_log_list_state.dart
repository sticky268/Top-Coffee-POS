import '../domain/audit_log_models.dart';

sealed class AuditLogListState {
  const AuditLogListState();
}

class AuditLogListLoading extends AuditLogListState {
  const AuditLogListLoading();
}

class AuditLogListLoaded extends AuditLogListState {
  const AuditLogListLoaded({
    required this.logs,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<AuditLogEntry> logs;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  AuditLogListLoaded copyWith({
    List<AuditLogEntry>? logs,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return AuditLogListLoaded(
      logs: logs ?? this.logs,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class AuditLogListError extends AuditLogListState {
  const AuditLogListError(this.message);

  final String message;
}