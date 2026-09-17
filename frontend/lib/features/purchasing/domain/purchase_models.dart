class PurchaseSupplier {
  const PurchaseSupplier({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
  });

  final int id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;

  factory PurchaseSupplier.fromJson(Map<String, dynamic> json) {
    return PurchaseSupplier(
      id: json['id'] as int,
      name: json['name'] as String,
      contactName: json['contact_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }
}

class PurchaseIngredient {
  const PurchaseIngredient({
    required this.id,
    required this.name,
    required this.currentStock,
  });

  final int id;
  final String name;
  final double currentStock;

  factory PurchaseIngredient.fromJson(Map<String, dynamic> json) {
    return PurchaseIngredient(
      id: json['id'] as int,
      name: json['name'] as String,
      currentStock: double.parse(
        json['current_stock'].toString(),
      ),
    );
  }
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.ingredientId,
    required this.quantity,
    required this.unitCost,
    required this.ingredient,
  });

  final int id;
  final int ingredientId;
  final double quantity;
  final double unitCost;
  final PurchaseIngredient ingredient;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    return PurchaseItem(
      id: json['id'] as int,
      ingredientId: json['ingredient_id'] as int,
      quantity: double.parse(
        json['quantity'].toString(),
      ),
      unitCost: double.parse(
        json['unit_cost'].toString(),
      ),
      ingredient: PurchaseIngredient.fromJson(
        json['ingredient'] as Map<String, dynamic>,
      ),
    );
  }
}

class Purchase {
  const Purchase({
    required this.id,
    required this.branchId,
    required this.supplierId,
    required this.createdBy,
    required this.totalCost,
    required this.purchasedAt,
    required this.supplier,
    required this.items,
  });

  final int id;
  final int branchId;
  final int supplierId;
  final int createdBy;
  final double totalCost;
  final DateTime purchasedAt;
  final PurchaseSupplier supplier;
  final List<PurchaseItem> items;

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] as int,
      branchId: json['branch_id'] as int,
      supplierId: json['supplier_id'] as int,
      createdBy: json['created_by'] as int,
      totalCost: double.parse(
        json['total_cost'].toString(),
      ),
      purchasedAt: DateTime.parse(
        json['purchased_at'] as String,
      ),
      supplier: PurchaseSupplier.fromJson(
        json['supplier'] as Map<String, dynamic>,
      ),
      items: (json['items'] as List)
          .map(
            (item) => PurchaseItem.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class PurchaseHistoryPage {
  const PurchaseHistoryPage({
    required this.purchases,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final List<Purchase> purchases;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasNextPage => currentPage < lastPage;

  factory PurchaseHistoryPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>;

    return PurchaseHistoryPage(
      purchases: (json['data'] as List)
          .map(
            (purchase) => Purchase.fromJson(
              purchase as Map<String, dynamic>,
            ),
          )
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      perPage: meta['per_page'] as int,
      total: meta['total'] as int,
    );
  }
}