/// Domain models for the POS catalog + cart. Framework-agnostic (no
/// Flutter imports) — same convention as features/auth/domain and
/// features/dashboard/domain.
library;

class PosCategory {
  const PosCategory({required this.id, required this.name, required this.sortOrder});

  final int id;
  final String name;
  final int sortOrder;

  factory PosCategory.fromJson(Map<String, dynamic> json) {
    return PosCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class PosProductVariant {
  const PosProductVariant({required this.id, required this.name, required this.price});

  final int id;
  final String name;

  /// Absolute resolved price for this variant (branch-effective base price
  /// plus the variant's delta) — the backend already does this math, see
  /// ProductController::index(), so this is a display-ready number.
  final double price;

  factory PosProductVariant.fromJson(Map<String, dynamic> json) {
    return PosProductVariant(
      id: json['id'] as int,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
    );
  }
}

class PosProductCategoryRef {
  const PosProductCategoryRef({required this.id, required this.name});

  final int id;
  final String name;

  factory PosProductCategoryRef.fromJson(Map<String, dynamic> json) {
    return PosProductCategoryRef(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class PosProduct {
  const PosProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.description,
    required this.category,
    required this.price,
    required this.variants,
  });

  final int id;
  final String name;
  final String? sku;
  final String? description;
  final PosProductCategoryRef? category;

  /// Branch-effective resolved price (price_override ?? base_price on the
  /// backend). For a product with variants this is the "base" figure —
  /// see ProductCard, which shows "From $X" when variants exist.
  final double price;
  final List<PosProductVariant> variants;

  bool get hasVariants => variants.isNotEmpty;

  factory PosProduct.fromJson(Map<String, dynamic> json) {
    return PosProduct(
      id: json['id'] as int,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      description: json['description'] as String?,
      category: json['category'] != null
          ? PosProductCategoryRef.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      price: (json['price'] as num).toDouble(),
      variants: (json['variants'] as List? ?? const [])
          .map((v) => PosProductVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One line in the cart: a product, an optional variant, and a quantity.
class CartItem {
  const CartItem({required this.product, this.variant, required this.quantity});

  final PosProduct product;
  final PosProductVariant? variant;
  final int quantity;

  /// Unit price for this line — the variant's resolved price if a variant
  /// was selected, otherwise the product's own resolved price.
  double get unitPrice => variant?.price ?? product.price;

  double get lineTotal => unitPrice * quantity;

  /// Identifies "the same cart line": same product AND same variant choice
  /// (or lack of one). Used to merge a repeated tap into a quantity
  /// increase instead of creating a duplicate line, and to target
  /// increment/decrement/remove actions — this is what guarantees a
  /// "Latte — Medium" line and a "Latte — Large" line never collapse into
  /// each other.
  String get lineKey => '${product.id}:${variant?.id ?? 'base'}';

  CartItem copyWith({int? quantity}) {
    return CartItem(product: product, variant: variant, quantity: quantity ?? this.quantity);
  }
}

/// Result of a successful POST /api/v1/orders — enough to show a
/// confirmation (order id, resolved total, change due for cash) without
/// needing a full order-detail fetch, which is out of scope for this task.
class OrderConfirmation {
  const OrderConfirmation({
    required this.orderId,
    required this.total,
    required this.paymentMethod,
    this.tendered,
    this.changeDue,
  });

  final int orderId;
  final double total;
  final String paymentMethod;
  final double? tendered;
  final double? changeDue;

  factory OrderConfirmation.fromJson(Map<String, dynamic> json) {
    final payment = json['payment'] as Map<String, dynamic>;
    return OrderConfirmation(
      orderId: json['id'] as int,
      total: (json['total'] as num).toDouble(),
      paymentMethod: payment['method'] as String,
      tendered: payment['tendered'] != null ? (payment['tendered'] as num).toDouble() : null,
      changeDue: payment['change_due'] != null ? (payment['change_due'] as num).toDouble() : null,
    );
  }
}
