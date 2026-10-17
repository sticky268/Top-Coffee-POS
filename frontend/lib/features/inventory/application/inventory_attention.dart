import '../domain/inventory_models.dart';

enum InventoryStockFilter { all, needsRestock, inactive }

class InventoryAttentionSummary {
  InventoryAttentionSummary(Iterable<InventoryIngredient> ingredients) {
    for (final ingredient in ingredients) {
      if (!ingredient.isActive) {
        inactive++;
      } else if (ingredient.currentStock <= 0) {
        outOfStock++;
        needsRestock++;
      } else if (ingredient.isLowStock) {
        needsRestock++;
      }
    }
  }

  int needsRestock = 0;
  int outOfStock = 0;
  int inactive = 0;
}

/// Keep empty stock ahead of low stock, without changing any stock balances.
List<InventoryIngredient> inventoryAttentionList(
  List<InventoryIngredient> ingredients, {
  String query = '',
  InventoryStockFilter filter = InventoryStockFilter.all,
}) {
  final search = query.trim().toLowerCase();
  final result = ingredients.where((ingredient) {
    final matchesFilter = switch (filter) {
      InventoryStockFilter.all => true,
      InventoryStockFilter.needsRestock =>
        ingredient.isActive &&
            (ingredient.isLowStock || ingredient.currentStock <= 0),
      InventoryStockFilter.inactive => !ingredient.isActive,
    };
    return matchesFilter &&
        (search.isEmpty ||
            ingredient.name.toLowerCase().contains(search) ||
            ingredient.unit.name.toLowerCase().contains(search) ||
            ingredient.unit.abbreviation.toLowerCase().contains(search));
  }).toList();
  int rank(InventoryIngredient ingredient) => !ingredient.isActive
      ? 3
      : ingredient.currentStock <= 0
      ? 0
      : ingredient.isLowStock
      ? 1
      : 2;
  result.sort((a, b) {
    final urgency = rank(a).compareTo(rank(b));
    if (urgency != 0) return urgency;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name == 0 ? a.id.compareTo(b.id) : name;
  });
  return result;
}
