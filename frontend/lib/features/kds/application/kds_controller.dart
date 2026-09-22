import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kds_repository.dart';
import 'kds_state.dart';

class KdsController extends Notifier<KdsState> {
  @override
  KdsState build() {
    Future.microtask(loadTickets);
    return const KdsState();
  }

  KdsRepository get _repository => ref.read(kdsRepositoryProvider);

  Future<void> loadTickets({int? branchId}) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final tickets = await _repository.getTickets(
        branchId: branchId,
      );

      state = state.copyWith(
        tickets: tickets,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh({int? branchId}) {
    return loadTickets(branchId: branchId);
  }

  Future<void> updateStatus({
    required int ticketId,
    required String status,
  }) async {
    if (state.updatingTicketId != null) {
      return;
    }

    state = state.copyWith(
      updatingTicketId: ticketId,
      clearError: true,
    );

    try {
      final updatedTicket = await _repository.updateTicketStatus(
        ticketId: ticketId,
        status: status,
      );

      final updatedTickets = state.tickets
          .map(
            (ticket) =>
                ticket.id == updatedTicket.id ? updatedTicket : ticket,
          )
          .toList();

      state = state.copyWith(
        tickets: updatedTickets,
        clearError: true,
        clearUpdatingTicket: true,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString(),
        clearUpdatingTicket: true,
      );
    }
  }
}

final kdsControllerProvider =
    NotifierProvider<KdsController, KdsState>(KdsController.new);
