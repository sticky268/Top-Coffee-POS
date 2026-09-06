import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/domain/auth_models.dart';

class CurrentBranchNotifier extends StateNotifier<BranchSummary?> {
  CurrentBranchNotifier(this._ref) : super(null) {
    _ref.listen<AuthState>(
      authControllerProvider,
      (_, next) => _syncWithAuth(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;

  void _syncWithAuth(AuthState authState) {
    if (authState is AuthAuthenticated) {
      final branches = authState.user.branches;

      if (branches.isEmpty) {
        state = null;
        return;
      }

      // Keep the current selection if the authenticated user still has it.
      if (state != null &&
          branches.any((branch) => branch.id == state!.id)) {
        return;
      }

      // Default to the user's first available branch.
      state = branches.first;
    } else {
      state = null;
    }
  }

  void selectBranch(BranchSummary branch) {
    state = branch;
  }
}

final currentBranchProvider =
    StateNotifierProvider<CurrentBranchNotifier, BranchSummary?>((ref) {
  return CurrentBranchNotifier(ref);
});