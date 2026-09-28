import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/reports_repository.dart';
import 'reports_state.dart';

enum ReportsDateRange {
  today,
  yesterday,
  last7Days,
  last30Days,
}

class ReportsController extends StateNotifier<ReportsState> {
  ReportsController(this._repository, this._ref)
      : super(const ReportsLoading()) {
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

    _initialization = _load(ReportsDateRange.today);
  }

  final ReportsRepository _repository;
  final Ref _ref;

  int? _branchId;

  ReportsDateRange _selectedRange = ReportsDateRange.today;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  ReportsDateRange get selectedRange => _selectedRange;

  Future<void> selectRange(ReportsDateRange range) {
    _selectedRange = range;

    final future = _load(range);
    _initialization = future;

    return future;
  }

  Future<void> refresh() {
    final future = _load(_selectedRange);
    _initialization = future;

    return future;
  }

  Future<void> _load(ReportsDateRange range) async {
    if (!mounted) return;

    state = const ReportsLoading();

    final dates = _dateRange(range);

    try {
      final report = await _repository.getReport(
        dateFrom: _formatDate(dates.$1),
        dateTo: _formatDate(dates.$2),
      );

      if (!mounted) return;

      state = ReportsLoaded(
        report: report,
        dateFrom: dates.$1,
        dateTo: dates.$2,
      );
    } catch (e) {
      if (!mounted) return;

      state = ReportsError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }

  static (DateTime, DateTime) _dateRange(ReportsDateRange range) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    switch (range) {
      case ReportsDateRange.today:
        return (
          todayDate,
          todayDate,
        );

      case ReportsDateRange.yesterday:
        final yesterday = todayDate.subtract(const Duration(days: 1));
        return (
          yesterday,
          yesterday,
        );

      case ReportsDateRange.last7Days:
        return (
          todayDate.subtract(const Duration(days: 6)),
          todayDate,
        );

      case ReportsDateRange.last30Days:
        return (
          todayDate.subtract(const Duration(days: 29)),
          todayDate,
        );
    }
  }

  static String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }
}

final reportsControllerProvider =
    StateNotifierProvider<ReportsController, ReportsState>((ref) {
  return ReportsController(
    ref.watch(reportsRepositoryProvider),
    ref,
  );
});
