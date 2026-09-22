import 'package:flutter/foundation.dart';

import '../domain/kds_models.dart';

@immutable
class KdsState {
  const KdsState({
    this.tickets = const [],
    this.isLoading = false,
    this.errorMessage,
    this.updatingTicketId,
  });

  final List<KitchenTicket> tickets;
  final bool isLoading;
  final String? errorMessage;
  final int? updatingTicketId;

  bool get isUpdating => updatingTicketId != null;

  KdsState copyWith({
    List<KitchenTicket>? tickets,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    int? updatingTicketId,
    bool clearUpdatingTicket = false,
  }) {
    return KdsState(
      tickets: tickets ?? this.tickets,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
      updatingTicketId: clearUpdatingTicket
          ? null
          : (updatingTicketId ?? this.updatingTicketId),
    );
  }
}
