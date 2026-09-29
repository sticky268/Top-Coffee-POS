import '../domain/branch_models.dart';

sealed class BranchListState {
  const BranchListState();
}

class BranchListLoading extends BranchListState {
  const BranchListLoading();
}

class BranchListLoaded extends BranchListState {
  const BranchListLoaded({
    required this.branches,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.isLoadingMore = false,
  });

  final List<Branch> branches;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingMore;

  bool get hasMore => currentPage < lastPage;

  BranchListLoaded copyWith({
    List<Branch>? branches,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingMore,
  }) {
    return BranchListLoaded(
      branches: branches ?? this.branches,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class BranchListError extends BranchListState {
  const BranchListError(this.message);

  final String message;
}
