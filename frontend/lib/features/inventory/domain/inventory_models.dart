class InventoryUnit {
  const InventoryUnit({
    required this.id,
    required this.name,
    required this.abbreviation,
  });

  final int id;
  final String name;
  final String abbreviation;

  factory InventoryUnit.fromJson(Map<String, dynamic> json) {
    return InventoryUnit(
      id: json['id'] as int,
      name: json['name'] as String,
      abbreviation: json['abbreviation'] as String,
    );
  }
}

class InventoryIngredient {
  const InventoryIngredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.reorderThreshold,
    required this.isLowStock,
    required this.isActive,
  });

  final int id;
  final String name;
  final InventoryUnit unit;
  final double currentStock;
  final double reorderThreshold;
  final bool isLowStock;
  final bool isActive;

  factory InventoryIngredient.fromJson(Map<String, dynamic> json) {
    return InventoryIngredient(
      id: json['id'] as int,
      name: json['name'] as String,
      unit: InventoryUnit.fromJson(
        json['unit'] as Map<String, dynamic>,
      ),
      currentStock: double.parse(json['current_stock'].toString()),
      reorderThreshold:
          double.parse(json['reorder_threshold'].toString()),
      isLowStock: json['is_low_stock'] as bool,
      isActive: json['is_active'] as bool,
    );
  }
}