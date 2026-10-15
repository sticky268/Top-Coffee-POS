import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'dart:async';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/receipt/receipt_action_service.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/receipt/customer_bill.dart';
import 'package:top_coffee_pos/core/widgets/receipt_action_buttons.dart';

class _ReceiptService extends Mock implements ReceiptActionService {}

void main() {
  testWidgets('uncertain receipt keeps paid state and directs cashier to inspect paper', (tester) async {
    final service = _ReceiptService();
    when(() => service.printReceipt(42, asCopy: false)).thenThrow(
      ReceiptPrintException(PrintStatus.uncertain, 'Printer confirmation was lost.'),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [receiptActionServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: Scaffold(body: Column(children: [
        Text('Payment Successful'),
        ReceiptActionButtons(orderId: 42, autoPrint: true),
      ]))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.text('Check Paper'), findsOneWidget);
    expect(find.text('Retry Print'), findsNothing);
    verify(() => service.printReceipt(42, asCopy: false)).called(1);
  });


  for (final autoPrint in [false, true]) {
    testWidgets('paid receipt autoPrint=$autoPrint never repeats on rebuild', (tester) async {
      final service = _ReceiptService();
      final pending = Completer<OrderReceipt>();
      when(() => service.printReceipt(42, asCopy: false))
          .thenAnswer((_) => pending.future);
      Widget screen() => ProviderScope(
        overrides: [receiptActionServiceProvider.overrideWithValue(service)],
        child: MaterialApp(home: Scaffold(body: ReceiptActionButtons(
          orderId: 42, autoPrint: autoPrint,
        ))),
      );
      await tester.pumpWidget(screen());
      await tester.pump();
      if (!autoPrint) {
        verifyNever(() => service.printReceipt(42, asCopy: false));
        return;
      }
      await tester.pumpWidget(screen());
      await tester.pump();
      verify(() => service.printReceipt(42, asCopy: false)).called(1);
      pending.completeError(StateError('Printer disconnected'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Payment is saved.'), findsOneWidget);
      expect(find.text('Retry Print'), findsOneWidget);
      const receipt = OrderReceipt(orderId: 42, uuid: 'sale',
        orderType: 'takeaway', status: 'completed', subtotal: 5,
        discountTotal: 0, total: 5, items: []);
      when(() => service.printReceipt(42, asCopy: false))
          .thenAnswer((_) async => receipt);
      await tester.tap(find.text('Retry Print'));
      await tester.pumpAndSettle();
      verify(() => service.printReceipt(42, asCopy: false)).called(1);
      expect(find.text('Retry Print'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('receipt actions are available only for completed orders', () {
    expect(canIssueReceiptForOrderStatus('completed'), isTrue);
    expect(canIssueReceiptForOrderStatus('held'), isFalse);
    expect(canIssueReceiptForOrderStatus('cancelled'), isFalse);
    expect(canIssueReceiptForOrderStatus('pending'), isFalse);
  });

  testWidgets('receipt action buttons expose print and electronic receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ReceiptActionButtons(orderId: 42, showHeading: true),
          ),
        ),
      ),
    );

    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Print Receipt'), findsOneWidget);
    expect(find.text('E-Receipt'), findsOneWidget);
    expect(
      find.text('Print a paid receipt or share a PDF E-Receipt.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'direct receipt copy requires confirmation before loading or printing',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: ReceiptActionButtons(orderId: 42)),
          ),
        ),
      );
      await tester.tap(find.text('Reprint COPY'));
      // The background print button is busy while confirmation is open.
      // Pump the dialog transition without waiting for its spinner to stop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Print a COPY?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Print Receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bill actions expose unpaid print and electronic bill', (
    tester,
  ) async {
    const bill = CustomerBill(
      orderType: 'takeaway',
      subtotal: 5,
      discountTotal: 0,
      total: 5,
      items: <CustomerBillLine>[
        CustomerBillLine(
          productName: 'Latte',
          quantity: 1,
          unitPrice: 5,
          lineTotal: 5,
        ),
      ],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: BillActionButtons(bill: bill, showHeading: true),
          ),
        ),
      ),
    );

    expect(find.text('Customer Bill'), findsOneWidget);
    expect(find.text('Print Bill'), findsOneWidget);
    expect(find.text('E-Bill'), findsOneWidget);
    expect(find.textContaining('Draft / Unpaid'), findsOneWidget);
  });
}
