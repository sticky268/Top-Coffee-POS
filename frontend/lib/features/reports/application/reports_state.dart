import '../domain/reports_models.dart';

sealed class ReportsState {
  const ReportsState();
}

class ReportsLoading extends ReportsState {
  const ReportsLoading();
}

class ReportsLoaded extends ReportsState {
  const ReportsLoaded({
    required this.report,
    required this.dateFrom,
    required this.dateTo,
  });

  final ReportsData report;
  final DateTime dateFrom;
  final DateTime dateTo;

  ReportsLoaded copyWith({
    ReportsData? report,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    return ReportsLoaded(
      report: report ?? this.report,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
    );
  }
}

class ReportsError extends ReportsState {
  const ReportsError(this.message);

  final String message;
}
