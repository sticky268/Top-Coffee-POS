import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import '../../support/memory_local_store.dart';

class MockApi extends Mock implements ApiClient {}

void main() {
  test(
    'cash without saved shift is blocked before outbox preparation or API send',
    () async {
      final store = MemoryLocalStore();
      final api = MockApi();
      final outbox = OrderOutbox(store, newUuid: () => 'should-not-be-used');
      addTearDown(outbox.close);
      final repository = ApiPosRepository(
        api,
        localStore: store,
        outbox: outbox,
        userId: () => 1,
        requireCashShift: () => true,
      );
      for (final method in ['cash', 'split']) {
        await expectLater(
          repository.createOrder(
            items: const [
              CartItem(
                product: PosProduct(
                  id: 1,
                  name: 'Coffee',
                  sku: null,
                  description: null,
                  category: null,
                  price: 10,
                  variants: [],
                ),
                quantity: 1,
              ),
            ],
            branchId: 2,
            paymentMethod: method,
            orderType: 'takeaway',
            tendered: 10,
            splitPayments: method == 'split'
                ? [
                    {'method': 'cash', 'amount': 5, 'tendered': 5},
                    {'method': 'card', 'amount': 5},
                  ]
                : null,
          ),
          throwsA(isA<ValidationException>()),
        );
      }
      verifyZeroInteractions(api);
      expect(await store.entries(''), isEmpty);
    },
  );
}
