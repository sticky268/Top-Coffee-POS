import 'order_outbox.dart';

/// Derived from the selected cashier and branch's durable outbox only.
class OrderSyncSummary {
  const OrderSyncSummary({
    required this.waiting,
    required this.needsReview,
    required this.confirmed,
    this.latestConfirmation,
  });

  factory OrderSyncSummary.fromOrders(List<PendingOrder> orders) {
    var waiting = 0;
    var needsReview = 0;
    var confirmed = 0;
    DateTime? latestConfirmation;
    for (final order in orders) {
      if (order.status == 'pending') {
        waiting++;
      } else if (order.status == 'synced') {
        confirmed++;
        final time = order.confirmedAt;
        if (time != null &&
            (latestConfirmation == null || time.isAfter(latestConfirmation))) {
          latestConfirmation = time;
        }
      } else {
        // Unknown states are never presented as confirmed or safe to discard.
        needsReview++;
      }
    }
    return OrderSyncSummary(
      waiting: waiting,
      needsReview: needsReview,
      confirmed: confirmed,
      latestConfirmation: latestConfirmation,
    );
  }

  final int waiting;
  final int needsReview;
  final int confirmed;
  final DateTime? latestConfirmation;

  bool get needsAttention => waiting > 0 || needsReview > 0;
  bool get hasUnconfirmed => needsAttention;

  String get description {
    if (!needsAttention) return 'All saved orders are confirmed by the server.';
    return [
      if (waiting > 0) '$waiting waiting for server confirmation',
      if (needsReview > 0) '$needsReview needing review',
    ].join(' · ');
  }
}
