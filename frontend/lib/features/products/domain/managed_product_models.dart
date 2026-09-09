/// Domain models for Product Management (create/update) — deliberately
/// distinct from PosProduct/PosProductVariant (features/pos/domain/
/// pos_models.dart).
///
/// Those catalog models represent GET /api/v1/products's response: a
/// branch-resolved, active-only view (a single `price`, no `is_active`,
/// no `base_price`, and each variant's `price` is an absolute resolved
/// number, not a delta). The management endpoints
/// (ProductController::store()/update(), via its private present()
/// method) return a genuinely different shape — `base_price`, `is_active`
/// on both the product and each variant, and `sku`/`price_delta` on
/// variants. Reusing PosProduct here would mean inventing fields that
/// don't exist on it. This file exists because the two shapes are
/// actually different, not as a duplicate of something already covered.
library;

import '../../pos/domain/pos_models.dart' show PosProduct, PosProductVariant;

class ManagedProductCategoryRef {
  const ManagedProductCategoryRef({required this.id, required this.name});

  final int id;
  final String name;

  factory ManagedProductCategoryRef.fromJson(Map<String, dynamic> json) {
    return ManagedProductCategoryRef(id: json['id'] as int, name: json['name'] as String);
  }
}

class ManagedProductVariant {
  const ManagedProductVariant({
    this.id,
    required this.name,
    this.sku,
    required this.priceDelta,
    this.isActive = true,
  });

  /// null for a variant not yet saved to the backend — a new row added
  /// in the form. Sending an entry without `id` tells the backend to
  /// create it (see ProductController::update()'s upsert-by-id logic).
  final int? id;
  final String name;
  final String? sku;
  final double priceDelta;
  final bool isActive;

  factory ManagedProductVariant.fromJson(Map<String, dynamic> json) {
    return ManagedProductVariant(
      id: json['id'] as int?,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      priceDelta: (json['price_delta'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'sku': (sku != null && sku!.trim().isNotEmpty) ? sku!.trim() : null,
      'price_delta': priceDelta,
      'is_active': isActive,
    };
  }

  ManagedProductVariant copyWith({
    String? name,
    String? sku,
    bool clearSku = false,
    double? priceDelta,
    bool? isActive,
  }) {
    return ManagedProductVariant(
      id: id,
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      priceDelta: priceDelta ?? this.priceDelta,
      isActive: isActive ?? this.isActive,
    );
  }

  /// A stable local key for the add/edit form's list rendering — the
  /// backend `id` if this variant is already saved, otherwise a marker
  /// derived from identity so newly-added, unsaved rows still have a
  /// distinct key.
  Object get formKey => id ?? identityHashCode(this);
}

class ManagedProduct {
  const ManagedProduct({
    this.id,
    required this.name,
    this.sku,
    this.description,
    required this.categoryId,
    this.category,
    required this.basePrice,
    this.isActive = true,
    this.variants = const [],
    this.imageUrl,
  });

  /// null for a not-yet-created product (the Add Product form).
  final int? id;
  final String name;
  final String? sku;
  final String? description;
  final int categoryId;

  /// Populated when parsed from a server response; not required to build
  /// a request (only [categoryId] is sent).
  final ManagedProductCategoryRef? category;
  final double basePrice;
  final bool isActive;
  final List<ManagedProductVariant> variants;
  final String? imageUrl;

  factory ManagedProduct.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['category'] as Map<String, dynamic>?;
    return ManagedProduct(
      id: json['id'] as int?,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      description: json['description'] as String?,
      categoryId: categoryJson?['id'] as int? ?? 0,
      category: categoryJson != null ? ManagedProductCategoryRef.fromJson(categoryJson) : null,
      basePrice: (json['base_price'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      variants: (json['variants'] as List? ?? const [])
          .map((v) => ManagedProductVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
      imageUrl: (json['images'] as List? ?? const []).isNotEmpty
          ? ((json['images'] as List).first as Map<String, dynamic>)['url'] as String?
          : null,
    );
  }

  /// Best-effort reconstruction from the catalog list's [PosProduct] —
  /// used to pre-fill the Edit form, since there is no
  /// GET /api/v1/products/{id} detail endpoint to fetch the true
  /// management shape.
  ///
  /// Known, deliberate approximations (documented here rather than
  /// hidden — see the delivery report for the same note):
  ///  - `basePrice` uses the catalog's branch-resolved `price`, which
  ///    equals the true base_price only when no branch price_override is
  ///    active. Branch-specific pricing is out of scope for this
  ///    milestone, so overrides aren't editable here anyway.
  ///  - `isActive` is always true — the catalog list only ever contains
  ///    already-active products (GET /products filters on is_active).
  ///  - Each variant's `priceDelta` is derived as `variant.price -
  ///    product.price`, exact only under the same no-override assumption
  ///    above. `sku` isn't exposed by the catalog list at all and starts
  ///    blank (editable).
  factory ManagedProduct.fromPosProduct(PosProduct product) {
    return ManagedProduct(
      id: product.id,
      name: product.name,
      sku: product.sku,
      description: product.description,
      categoryId: product.category?.id ?? 0,
      category:
          product.category != null ? ManagedProductCategoryRef(id: product.category!.id, name: product.category!.name) : null,
      basePrice: product.price,
      isActive: true,
      variants: product.variants
          .map((PosProductVariant v) => ManagedProductVariant(
                id: v.id,
                name: v.name,
                sku: null,
                priceDelta: v.price - product.price,
                isActive: true,
              ))
          .toList(),
    );
  }

  /// Always includes every field explicitly (nulling out empty optional
  /// strings rather than omitting them) — used for both create and
  /// update, so the form's "what you see is what gets saved" holds for
  /// edits too (PATCH's `sometimes` validation only skips fields whose
  /// key is entirely absent from the payload; omitting sku/description
  /// here would leave a previously-set value untouched instead of
  /// clearing it).
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category_id': categoryId,
      'sku': (sku != null && sku!.trim().isNotEmpty) ? sku!.trim() : null,
      'description': (description != null && description!.trim().isNotEmpty) ? description!.trim() : null,
      'base_price': basePrice,
      'is_active': isActive,
      'variants': variants.map((v) => v.toJson()).toList(),
    };
  }

  ManagedProduct copyWith({
    String? name,
    String? sku,
    bool clearSku = false,
    String? description,
    bool clearDescription = false,
    int? categoryId,
    ManagedProductCategoryRef? category,
    double? basePrice,
    bool? isActive,
    List<ManagedProductVariant>? variants,
    String? imageUrl,
  }) {
    return ManagedProduct(
      id: id,
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      description: clearDescription ? null : (description ?? this.description),
      categoryId: categoryId ?? this.categoryId,
      category: category ?? this.category,
      basePrice: basePrice ?? this.basePrice,
      isActive: isActive ?? this.isActive,
      variants: variants ?? this.variants,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
