import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/inventory/application/inventory_attention.dart';
import 'package:top_coffee_pos/features/inventory/domain/inventory_models.dart';

InventoryIngredient ingredient(int id, String name, double stock,
    {bool active = true, bool low = false}) => InventoryIngredient(
  id: id, name: name,
  unit: const InventoryUnit(id: 1, name: 'Kilogram', abbreviation: 'kg'),
  currentStock: stock, reorderThreshold: 2, isLowStock: low, isActive: active,
);

void main() {
  final items = [
    ingredient(1, 'Healthy', 10),
    ingredient(2, 'Low', 1, low: true),
    ingredient(3, 'Empty', 0, low: true),
    ingredient(4, 'Retired', 0, low: true, active: false),
    ingredient(5, 'Negative', -1, low: true),
  ];
  test('restocking excludes inactive stock and counts empty stock once', () {
    final summary = InventoryAttentionSummary(items);
    expect(summary.needsRestock, 3);
    expect(summary.outOfStock, 2);
    expect(summary.inactive, 1);
    expect(inventoryAttentionList(items,
      filter: InventoryStockFilter.needsRestock).map((item) => item.id),
      [3, 5, 2]);
  });
  test('all items sort empty, low, healthy, inactive without modifying balances', () {
    expect(inventoryAttentionList(items).map((item) => item.id), [3, 5, 2, 1, 4]);
    expect(items.map((item) => item.id), [1, 2, 3, 4, 5]);
    expect(items.map((item) => item.currentStock), [10, 1, 0, 0, -1]);
  });
  test('search combines with restock filter and supports the unit', () {
    expect(inventoryAttentionList(items, query: ' HEALTHY ',
      filter: InventoryStockFilter.needsRestock), isEmpty);
    expect(inventoryAttentionList(items, query: ' KG ',
      filter: InventoryStockFilter.needsRestock), hasLength(3));
    expect(inventoryAttentionList(items, query: 'ret',
      filter: InventoryStockFilter.inactive).single.id, 4);
  });
  test('zero stock still needs attention if legacy low-stock flag is false', () {
    final legacy = [ingredient(6, 'Legacy', 0)];
    expect(InventoryAttentionSummary(legacy).needsRestock, 1);
    expect(inventoryAttentionList(legacy,
      filter: InventoryStockFilter.needsRestock), hasLength(1));
  });
}
