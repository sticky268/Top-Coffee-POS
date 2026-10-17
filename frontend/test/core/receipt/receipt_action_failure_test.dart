import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/core/receipt/receipt_action_service.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import '../../support/memory_local_store.dart';

class _Repository extends Mock implements PosRepository {}
class _FailedPrinter extends PrinterService {
  @override
  Future<Map<String, dynamic>> prepareReceipt(OrderReceipt receipt) async => {'total': '10.00'};
  @override
  Future<void> connect(String ipAddress) async => throw StateError('Printer disconnected');
  @override
  Future<void> disconnect() async {}
}

void main() {
  test('queued printer failures reach the cashier instead of reporting success', () async {
    final repository = _Repository();
    const receipt = OrderReceipt(orderId: 1, uuid: 'sale', orderType: 'takeaway',
      status: 'completed', subtotal: 10, discountTotal: 0, total: 10,
      branchId: 2, branchCode: 'B', items: []);
    when(() => repository.getOrderReceipt(orderId: 1)).thenAnswer((_) async => receipt);
    const scope = (userId: 1, branchId: 2);
    final printer = _FailedPrinter();
    final queue = PrintQueue(MemoryLocalStore(), printer, () => scope,
      (_) async => '192.0.2.1');
    addTearDown(queue.dispose);
    final service = ReceiptActionService(repository, printerService: printer,
      printQueue: queue, printScope: () => scope, branchCode: () => 'B');
    await expectLater(service.printReceipt(1), throwsA(isA<StateError>()));
    expect((await queue.list(scope)).single.status, PrintStatus.failed);
  });
}
