import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/widgets/cash_drawer_status.dart';

void main() {
  testWidgets('hardware progress and warning leave payment completed visible', (tester) async {
    final result = Completer<String?>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const Text('Payment Successful'), CashDrawerStatus(result: result.future),
    ]))));
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.textContaining('Sending cash drawer command'), findsOneWidget);
    result.complete('Payment completed. Check the drawer.');
    await tester.pumpAndSettle();
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.text('Payment completed. Check the drawer.'), findsOneWidget);
  });
}
