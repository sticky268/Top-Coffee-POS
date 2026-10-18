import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/sales_reports_repository.dart';
import '../domain/sales_report.dart';

class SalesReportsController extends StateNotifier<AsyncValue<SalesReport>> {
  SalesReportsController(this._repository, this._ref)
      : super(const AsyncLoading()) {
    _ref.listen(currentBranchProvider, (previous, next) {
      if (previous?.id != next?.id) {
        // Staff/category choices may not belong to the next branch.
        query = query.filters();
        refresh();
      }
    });
    initialization = refresh();
  }
  final SalesReportsRepository _repository;
  final Ref _ref;
  SalesReportQuery query = const SalesReportQuery();
  late Future<void> initialization;
  int _generation = 0;

  Future<void> select(SalesReportQuery next) {
    query = next;
    return refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final selected = query;
    final branch = _ref.read(currentBranchProvider)?.id;
    state = const AsyncLoading();
    try {
      final report = await _repository.load(selected, branch);
      if (mounted && generation == _generation) state = AsyncData(report);
    } catch (error, stack) {
      if (mounted && generation == _generation) {
        state = AsyncError(
            error is ApiException
                ? error.message
                : 'Could not load reports. Check the connection and retry.',
            stack);
      }
    }
  }
}

final salesReportsControllerProvider =
    StateNotifierProvider<SalesReportsController, AsyncValue<SalesReport>>(
        (ref) => SalesReportsController(
            ref.watch(salesReportsRepositoryProvider), ref));
