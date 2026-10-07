import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/widgets/receipt_action_buttons.dart';

void main() {
  test('receipt actions are available only for completed orders', () {
    expect(canIssueReceiptForOrderStatus('completed'), isTrue);
    expect(canIssueReceiptForOrderStatus('held'), isFalse);
    expect(canIssueReceiptForOrderStatus('cancelled'), isFalse);
    expect(canIssueReceiptForOrderStatus('pending'), isFalse);
  });

  testWidgets('receipt action buttons expose print and electronic receipt',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ReceiptActionButtons(
              orderId: 42,
              showHeading: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Print Receipt'), findsOneWidget);
    expect(find.text('E-Receipt'), findsOneWidget);
    expect(
      find.text('Print a paper copy or share a PDF E-Receipt.'),
      findsOneWidget,
    );
  });
}
