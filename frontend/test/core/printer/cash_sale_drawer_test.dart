import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/printer/cash_sale_drawer.dart';
import 'package:top_coffee_pos/core/printer/print_queue.dart';
import 'package:top_coffee_pos/core/printer/printer_service.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import '../../support/memory_local_store.dart';

class _Printer extends PrinterService {
  int pulses = 0;
  bool fail = false;
  Future<void> Function()? connecting;
  @override
  Future<void> connect(String ip) async {
    await connecting?.call();
    if (fail) throw StateError('Printer offline');
  }
  @override
  Future<void> openCashDrawer() async { pulses++; }
  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {}
  @override
  Future<void> disconnect() async {}
}
class _FullStore extends MemoryLocalStore {
  @override
  Future<void> write(String key, String value) async => throw StateError('Storage full');
}

void main() {
  const selected = (userId: 1, branchId: 2);
  late PrintScope? scope;
  late MemoryLocalStore store;
  late _Printer printer;
  late PrintQueue queue;
  late CashSaleDrawer drawer;
  OrderConfirmation sale({int id = 42, String method = 'cash',
      String status = 'completed', double total = 5,
      List<PaymentConfirmation> payments = const []}) =>
    OrderConfirmation(orderId: id, total: total, paymentMethod: method,
      status: status, payments: payments);
  setUp(() {
    scope = selected; store = MemoryLocalStore(); printer = _Printer();
    queue = PrintQueue(store, printer, () => scope, (_) async => 'ip');
    drawer = CashSaleDrawer(queue, () => scope, (_) async => 'ip');
  });
  tearDown(() => queue.dispose());

  test('one cash sale pulse survives duplicate callbacks and queue recreation', () async {
    await Future.wait([drawer.afterPayment(sale(), 1, 2), drawer.afterPayment(sale(), 1, 2)]);
    expect(printer.pulses, 1);
    final event = (await queue.drawerJournal.list(selected)).single;
    expect(event.orderId, 42);
    expect(event.source, 'cash_sale');
    expect(event.status, 'command_sent');
    final restarted = PrintQueue(store, printer, () => scope, (_) async => 'ip');
    addTearDown(restarted.dispose);
    await CashSaleDrawer(restarted, () => scope, (_) async => 'ip').afterPayment(sale(), 1, 2);
    expect(printer.pulses, 1);
    await drawer.afterPayment(sale(id: 43), 1, 2);
    expect(printer.pulses, 2);
  });
  test('card QR held and zero-total orders never pulse', () async {
    for (final confirmation in [
      sale(method: 'card'), sale(method: 'qr'), sale(status: 'held'),
      sale(status: 'cancelled'), sale(total: 0),
    ]) { await drawer.afterPayment(confirmation, 1, 2); }
    expect(printer.pulses, 0);
    expect(store.values, isEmpty);
  });
  test('a split payment with completed positive cash pulses once', () async {
    await drawer.afterPayment(sale(method: 'split', payments: const [
      PaymentConfirmation(id: 1, method: 'cash', amount: 2, status: 'completed'),
      PaymentConfirmation(id: 2, method: 'card', amount: 3, status: 'completed'),
    ]), 1, 2);
    expect(printer.pulses, 1);
    await drawer.afterPayment(sale(id: 44, method: 'split', payments: const [
      PaymentConfirmation(id: 3, method: 'cash', amount: 2, status: 'failed'),
      PaymentConfirmation(id: 4, method: 'card', amount: 3, status: 'completed'),
    ]), 1, 2);
    expect(printer.pulses, 1);
  });
  test('offline printer warns but never automatically retries that sale', () async {
    printer.fail = true;
    expect(await drawer.afterPayment(sale(), 1, 2), contains('Payment completed.'));
    printer.fail = false;
    await drawer.afterPayment(sale(), 1, 2);
    await queue.resumeWaiting(selected);
    expect(printer.pulses, 0);
    await queue.openCashDrawer(selected, () async => 'ip', () {}, reason: 'Check drawer');
    expect(printer.pulses, 1); // An explicit manual opening remains available.
  });
  test('wrong cashier or branch and a switch during connection prevent the pulse', () async {
    expect(await drawer.afterPayment(sale(), 9, 2), isNotNull);
    printer.connecting = () async { scope = (userId: 1, branchId: 3); };
    expect(await drawer.afterPayment(sale(), 1, 2), isNotNull);
    expect(printer.pulses, 0);
  });
  test('unable to persist the consumed attempt prevents a pulse', () async {
    final full = PrintQueue(_FullStore(), printer, () => scope, (_) async => 'ip');
    addTearDown(full.dispose);
    expect(await CashSaleDrawer(full, () => scope, (_) async => 'ip')
        .afterPayment(sale(), 1, 2), cashDrawerFailureMessage);
    expect(printer.pulses, 0);
  });
  test('printing and making a receipt copy cannot repeat the drawer command', () async {
    await drawer.afterPayment(sale(), 1, 2);
    final job = await queue.enqueue(selected: selected, documentId: 'receipt:42',
      reference: '42', payload: {});
    await queue.send(job.id, selected);
    final copy = await queue.copy(job.id, selected);
    await queue.send(copy.id, selected);
    await queue.resumeWaiting(selected);
    expect(printer.pulses, 1);
  });
}
