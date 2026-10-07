import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kds_repository.dart';
import 'kds_state.dart';

class KdsController extends Notifier<KdsState> {
  int _requestVersion = 0;
  int? _loadedBranchId;
  bool _hasLoadedBranch = false;

  @override
  KdsState build() {
    return const KdsState();
  }

  KdsRepository get _repository => ref.read(kdsRepositoryProvider);

  Future<void> loadTickets({int? branchId}) async {
    final branchChanged = !_hasLoadedBranch || branchId != _loadedBranchId;
    if (state.updatingTicketId != null && !branchChanged) return;
    final requestVersion = ++_requestVersion;
    _loadedBranchId = branchId;
    _hasLoadedBranch = true;
    state = state.copyWith(
      tickets: branchChanged ? const [] : null,
      isLoading: true,
      clearUpdatingTicket: branchChanged,
      clearError: true,
    );

    try {
      final tickets = await _repository.getTickets(
        branchId: branchId,
      );

      if (requestVersion != _requestVersion) return;
      state = state.copyWith(
        tickets: tickets,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (requestVersion != _requestVersion) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh({int? branchId}) {
    return loadTickets(branchId: branchId);
  }

  Future<void> acknowledgeCancellation({required int ticketId}) async {
    if (state.updatingTicketId != null) return;
    final operationVersion = ++_requestVersion;
    state = state.copyWith(updatingTicketId: ticketId, clearError: true);
    try {
      await _repository.acknowledgeCancellation(ticketId: ticketId);
      if (operationVersion != _requestVersion) return;
      state = state.copyWith(
        isLoading: false,
        tickets: state.tickets.where((ticket) => ticket.id != ticketId).toList(),
        clearUpdatingTicket: true,
        clearError: true,
      );
    } catch (e) {
      if (operationVersion != _requestVersion) return;
      state = state.copyWith(
        errorMessage: e.toString(),
        clearUpdatingTicket: true,
      );
      rethrow;
    }
  }

  Future<void> updateStatus({
    required int ticketId,
    required String status,
  }) async {
    if (state.updatingTicketId != null) {
      return;
    }
    final operationVersion = ++_requestVersion;

    state = state.copyWith(
      updatingTicketId: ticketId,
      clearError: true,
    );

    try {
      await _repository.updateTicketStatus(
        ticketId: ticketId,
        status: status,
      );
      if (operationVersion != _requestVersion) return;

      final updatedTickets = state.tickets
          .map(
            (ticket) =>
                ticket.id == ticketId ? ticket.copyWith(status: status) : ticket,
          )
          .toList();

      state = state.copyWith(
        isLoading: false,
        tickets: updatedTickets,
        clearError: true,
        clearUpdatingTicket: true,
      );
    } catch (e) {
      if (operationVersion != _requestVersion) return;
      state = state.copyWith(
        errorMessage: e.toString(),
        clearUpdatingTicket: true,
      );
    }
  }
}

final kdsControllerProvider =
    NotifierProvider<KdsController, KdsState>(KdsController.new);
