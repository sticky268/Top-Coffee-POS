import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/operations/presentation/operation_display.dart';

void main() {
  const user = AuthenticatedUser(
    id: 7,
    name: 'Sophea',
    email: 'cashier@example.invalid',
    roles: [],
    permissions: [],
    branches: [],
  );

  test('saved financial actions use clear labels without changing requests', () {
    final examples = {
      '/shifts': 'Open shift',
      '/shifts/3/close': 'Close shift',
      '/shifts/3/review': 'Review shift',
      '/stock/count': 'Stock count',
      '/stock/transfer': 'Stock transfer',
      '/orders/8/refund': 'Payment refund',
      '/orders/8/additional-charge': 'Additional payment',
      '/unknown/action': 'Saved action',
    };
    for (final entry in examples.entries) {
      final operation = {'path': entry.key, 'uuid': 'original-request'};
      expect(savedOperationTitle(operation), entry.value);
      expect(operation, {'path': entry.key, 'uuid': 'original-request'});
    }
    expect(
      savedOperationTitle({
        'path': '/shifts/3/movements',
        'payload': {'type': 'out'},
      }),
      'Remove cash from drawer',
    );
    expect(
      savedOperationTitle({
        'path': '/shifts/3/movements',
        'payload': {'type': 'in'},
      }),
      'Add cash to drawer',
    );
  });

  test('cashier names come from the server with safe legacy fallback', () {
    expect(shiftCashierName({'user_id': 7}, user), 'Sophea');
    expect(
      shiftCashierName({'user_id': 9, 'cashier_name': ' Dara '}, user),
      'Dara',
    );
    expect(
      shiftCashierName({'user_id': 9, 'cashier_name': ''}, user),
      'Cashier name unavailable',
    );
  });

  test('times are formatted in device time and invalid values stay unknown', () {
    final utc = DateTime.utc(2026, 10, 15, 23, 40);
    final expected = DateFormat.yMMMd().add_jm().format(utc.toLocal());
    expect(operationDeviceTime(utc.toIso8601String()), expected);
    expect(operationDeviceTime(utc), expected);
    expect(operationDeviceTime(null), 'Not available');
    expect(operationDeviceTime('not a timestamp'), 'Not available');
  });

  test('cash differences distinguish shortage, overage, match and unavailable', () {
    expect(cashDifferenceDescription('-0.01'), '\$0.01 short');
    expect(cashDifferenceDescription(1.25), '\$1.25 over');
    expect(cashDifferenceDescription(0), 'Cash count matches');
    expect(cashDifferenceDescription(null), 'Difference unavailable');
    expect(cashDifferenceDescription(double.nan), 'Difference unavailable');
  });
}
