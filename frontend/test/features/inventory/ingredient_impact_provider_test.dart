import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/inventory/application/inventory_list_controller.dart';
import 'package:top_coffee_pos/features/inventory/data/ingredient_impact.dart';

class _Api extends Mock implements ApiClient {}
const _scope = (userId: 1, branchId: 2);

void main() {
  test('scope mismatch blocks the request before network access', () async {
    final api = _Api();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      inventoryScopeProvider.overrideWith((ref) => (userId: 1, branchId: 3)),
    ]);
    addTearDown(container.dispose);
    await expectLater(container.read(ingredientImpactProvider((
      ingredientId: 4, scope: _scope, afterId: null,
    )).future), throwsA(isA<AuthException>()));
    verifyNever(() => api.request<Response<dynamic>>(any()));
  });

  test('response for a different ingredient or branch is rejected', () async {
    for (final wrong in [
      {'branch_id': 3, 'ingredient_id': 4},
      {'branch_id': 2, 'ingredient_id': 99},
    ]) {
      final api = _Api();
      when(() => api.request<Response<dynamic>>(any())).thenAnswer((_) async =>
        Response(requestOptions: RequestOptions(path: '/ingredients/4/products'),
          data: {...wrong, 'data': [], 'meta': {'next_after_id': null}}));
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        inventoryScopeProvider.overrideWith((ref) => _scope),
      ]);
      await expectLater(container.read(ingredientImpactProvider((
        ingredientId: 4, scope: _scope, afterId: null,
      )).future), throwsA(isA<FormatException>()));
      container.dispose();
    }
  });
}
