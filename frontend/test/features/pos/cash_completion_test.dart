import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import '../../support/memory_local_store.dart';

class _Api extends Mock implements ApiClient {}
void main() {
  late _Api api;
  const product = PosProduct(id: 1, name: 'Coffee', sku: null,
    description: null, category: null, price: 5, variants: []);
  Response<dynamic> response({String status = 'completed', String method = 'cash'}) =>
    Response(data: {'data': {'id': 42, 'uuid': 'order-42', 'order_type': 'takeaway',
      'status': status, 'subtotal': 5, 'discount_total': 0, 'total': 5,
      'items': [], 'payment': {'method': method, 'amount': 5, 'status': 'completed'}}},
      requestOptions: RequestOptions(path: '/orders'));
  Future<OrderConfirmation> pay(ApiPosRepository repo) =>
    repo.createOrder(items: const [CartItem(product: product, quantity: 1)],
      paymentMethod: 'cash', orderType: 'takeaway', branchId: 2);
  setUp(() { api = _Api(); });

  test('drawer starts only after server confirmation and never delays paid status', () async {
    final server = Completer<Response<dynamic>>();
    final hardware = Completer<String?>();
    var calls = 0;
    when(() => api.request<Response<dynamic>>(any())).thenAnswer((_) => server.future);
    final repo = ApiPosRepository(api, userId: () => 1,
      onCompleted: (confirmation, user, branch) {
        calls++; expect(user, 1); expect(branch, 2);
        return hardware.future;
      });
    final pending = pay(repo);
    expect(calls, 0);
    server.complete(response());
    final paid = await pending;
    expect(paid.orderId, 42);
    expect(calls, 1);
    hardware.complete('Payment completed. Printer offline.');
    expect(await paid.cashDrawerResult, contains('Payment completed.'));
  });
  test('drawer exception preserves successful confirmation and gives a warning', () async {
    when(() => api.request<Response<dynamic>>(any())).thenAnswer((_) async => response());
    final repo = ApiPosRepository(api, userId: () => 1,
      onCompleted: (confirmation, userId, branchId) async => throw StateError('Printer error'));
    final paid = await pay(repo);
    expect(paid.orderId, 42);
    expect(await paid.cashDrawerResult, contains('Payment completed.'));
  });
  test('failed or offline queued requests never trigger the drawer', () async {
    when(() => api.request<Response<dynamic>>(any())).thenThrow(const NetworkException());
    var calls = 0;
    final store = MemoryLocalStore();
    final outbox = OrderOutbox(store);
    final repo = ApiPosRepository(api, localStore: store, outbox: outbox, userId: () => 1,
      onCompleted: (confirmation, userId, branchId) async { calls++; return null; });
    await expectLater(pay(repo), throwsA(isA<QueuedOrderException>()));
    expect(calls, 0);
  });
  test('held saves and receipt reads do not open; completed held payment does', () async {
    when(() => api.request<Response<dynamic>>(any())).thenAnswer((_) async => response());
    var calls = 0;
    final repo = ApiPosRepository(api, userId: () => 1,
      onCompleted: (confirmation, userId, branchId) async { calls++; return null; });
    await repo.holdOrder(items: const [CartItem(product: product, quantity: 1)],
      orderType: 'dine_in', tableId: 3, branchId: 2);
    await repo.getOrderReceipt(orderId: 42);
    expect(calls, 0);
    final paid = await repo.payHeldOrder(orderId: 42, paymentMethod: 'cash', branchId: 2);
    await paid.cashDrawerResult;
    expect(calls, 1);
  });
  test('server cash confirmation is authoritative over the requested payment method', () async {
    when(() => api.request<Response<dynamic>>(any()))
      .thenAnswer((_) async => response(method: 'qr'));
    var calls = 0;
    final repo = ApiPosRepository(api, userId: () => 1,
      onCompleted: (confirmation, userId, branchId) async { calls++; return null; });
    final paid = await pay(repo);
    expect(paid.cashDrawerResult, isNull);
    expect(calls, 0);
  });
}
