import '../domain/staff_models.dart';

sealed class StaffListState {
  const StaffListState();
}

class StaffListLoading extends StaffListState {
  const StaffListLoading();
}

class StaffListLoaded extends StaffListState {
  const StaffListLoaded({
    required this.staff,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<StaffMember> staff;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  StaffListLoaded copyWith({
    List<StaffMember>? staff,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return StaffListLoaded(
      staff: staff ?? this.staff,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class StaffListError extends StaffListState {
  const StaffListError(this.message);

  final String message;
}
