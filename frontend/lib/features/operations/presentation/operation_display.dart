import 'package:intl/intl.dart';

import '../../auth/domain/auth_models.dart';

/// Display labels only. The original request path and payload stay unchanged.
String savedOperationTitle(Map<String, dynamic> operation) {
  final path = operation['path'];
  final payload = operation['payload'];
  if (path == '/shifts') return 'Open shift';
  if (path is! String) return 'Saved action';
  if (RegExp(r'^/shifts/\d+/movements$').hasMatch(path)) {
    final type = payload is Map ? payload['type'] : null;
    return type == 'in'
        ? 'Add cash to drawer'
        : type == 'out'
        ? 'Remove cash from drawer'
        : 'Cash movement';
  }
  if (RegExp(r'^/shifts/\d+/close$').hasMatch(path)) return 'Close shift';
  if (RegExp(r'^/shifts/\d+/review$').hasMatch(path)) return 'Review shift';
  if (path == '/stock/count') return 'Stock count';
  if (path == '/stock/transfer') return 'Stock transfer';
  if (RegExp(r'^/orders/\d+/refund$').hasMatch(path)) {
    return 'Payment refund';
  }
  if (RegExp(r'^/orders/\d+/additional-charge$').hasMatch(path)) {
    return 'Additional payment';
  }
  return 'Saved action';
}

String operationDeviceTime(Object? value) {
  final time = value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  return time == null
      ? 'Not available'
      : DateFormat.yMMMd().add_jm().format(time.toLocal());
}

String shiftCashierName(
  Map<String, dynamic> shift,
  AuthenticatedUser currentUser,
) {
  final name = shift['cashier_name'];
  if (name is String && name.trim().isNotEmpty) return name.trim();
  if (shift['user_id'] == currentUser.id) return currentUser.name;
  return 'Cashier name unavailable';
}

String cashDifferenceDescription(Object? value) {
  final amount = num.tryParse(value?.toString() ?? '');
  if (amount == null || !amount.isFinite) return 'Difference unavailable';
  final cents = (amount * 100).round();
  if (cents == 0) return 'Cash count matches';
  final money = NumberFormat.currency(symbol: '\$').format(cents.abs() / 100);
  return cents < 0 ? '$money short' : '$money over';
}
