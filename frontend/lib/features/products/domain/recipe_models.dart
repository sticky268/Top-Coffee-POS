class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.name,
    required this.unitId,
    required this.unitName,
    required this.unitAbbreviation,
  });

  final int id;
  final String name;
  final int unitId;
  final String unitName;
  final String unitAbbreviation;

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] as Map<String, dynamic>;

    return RecipeIngredient(
      id: json['id'] as int,
      name: json['name'] as String,
      unitId: json['unit_id'] as int,
      unitName: unit['name'] as String,
      unitAbbreviation: unit['abbreviation'] as String,
    );
  }
}

class RecipeItem {
  const RecipeItem({
    this.id,
    required this.ingredientId,
    required this.ingredient,
    required this.quantityUsed,
  });

  final int? id;
  final int ingredientId;
  final RecipeIngredient ingredient;
  final double quantityUsed;

  factory RecipeItem.fromJson(Map<String, dynamic> json) {
    return RecipeItem(
      id: json['id'] as int?,
      ingredientId: json['ingredient_id'] as int,
      ingredient: RecipeIngredient.fromJson(
        json['ingredient'] as Map<String, dynamic>,
      ),
      quantityUsed: double.parse(
        json['quantity_used'].toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ingredient_id': ingredientId,
      'quantity_used': quantityUsed,
    };
  }

  RecipeItem copyWith({
    int? id,
    int? ingredientId,
    RecipeIngredient? ingredient,
    double? quantityUsed,
  }) {
    return RecipeItem(
      id: id ?? this.id,
      ingredientId: ingredientId ?? this.ingredientId,
      ingredient: ingredient ?? this.ingredient,
      quantityUsed: quantityUsed ?? this.quantityUsed,
    );
  }
}