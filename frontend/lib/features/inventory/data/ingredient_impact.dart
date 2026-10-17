import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import '../application/inventory_list_controller.dart';

class IngredientProductLink {
  const IngredientProductLink({required this.id, required this.name});
  final int id;
  final String name;
}

class IngredientImpactPage {
  const IngredientImpactPage({required this.products, this.nextAfterId});
  final List<IngredientProductLink> products;
  final int? nextAfterId;

  factory IngredientImpactPage.fromJson(Map<String, dynamic> json) {
    final items = json['data'] as List;
    final meta = json['meta'] as Map;
    if (items.length > 20) {
      throw const FormatException('Recipe links exceeded the page limit.');
    }
    return IngredientImpactPage(
      products: items.map((item) => IngredientProductLink(
        id: item['id'] as int, name: item['name'] as String,
      )).toList(),
      nextAfterId: meta['next_after_id'] as int?,
    );
  }
}

typedef IngredientImpactQuery = ({
  int ingredientId, InventoryScope scope, int? afterId,
});

final ingredientImpactProvider = FutureProvider.autoDispose
    .family<IngredientImpactPage, IngredientImpactQuery>((ref, query) async {
  final scope = ref.watch(inventoryScopeProvider);
  if (scope == null || scope != query.scope) {
    throw const AuthException('Select this ingredient’s branch to view its recipe links.');
  }
  final api = ref.watch(apiClientProvider);
  final response = await api.request((dio) => dio.get(
    '/ingredients/${query.ingredientId}/products',
    queryParameters: {
      'branch_id': scope.branchId,
      if (query.afterId != null) 'after_id': query.afterId,
    },
  ));
  final json = Map<String, dynamic>.from(response.data as Map);
  if (json['branch_id'] != scope.branchId ||
      json['ingredient_id'] != query.ingredientId) {
    throw const FormatException('Recipe links belong to a different branch or ingredient.');
  }
  return IngredientImpactPage.fromJson(json);
});
