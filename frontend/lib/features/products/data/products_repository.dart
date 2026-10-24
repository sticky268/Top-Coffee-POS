import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
// Deliberately reusing PosCategory/PosProduct/PosProductVariant rather
// than redefining identical models here: this screen calls the exact same
// GET /api/v1/categories and GET /api/v1/products endpoints as the POS
// module, with the exact same response shape, so separate model classes
// would just be copies. This is read-only reuse of value types — nothing
// in pos/ is modified, and this repository/controller are independent of
// PosRepository/PosCatalogController (see products_controller.dart for
// why sharing that provider instance would be a real bug, not just
// duplication).
import '../../pos/domain/pos_models.dart';
import '../domain/managed_product_models.dart';
import '../domain/recipe_models.dart';

abstract class ProductsRepository {
  /// [branchId]: forwarded as the `branch_id` query param. When omitted,
  /// the backend falls back to the authenticated user's primary branch —
  /// passing it explicitly is what lets the app's branch switcher change
  /// which branch's catalog this screen shows.
  Future<List<PosCategory>> getCategories({int? branchId});
  Future<List<PosProduct>> getProducts({int? branchId});

  Future<PosCategory> createCategory({
    required int branchId,
    required String name,
    int sortOrder = 0,
  });
  Future<PosCategory> updateCategory({
    required int categoryId,
    String? name,
    int? sortOrder,
    bool? isActive,
  });

  Future<void> deleteCategory({required int categoryId});

  /// POST /api/v1/products
  ///
  /// [branchIds]: without at least one branch assigned, the backend
  /// creates the product with zero branch_product rows — and
  /// GET /api/v1/products requires a matching branch_product row to
  /// return a product at all (see ProductController::index()'s
  /// whereHas('branches', ...)). A product created with no branch would
  /// be permanently invisible in the catalog. This milestone still has no
  /// branch-selection UI (by design), so the caller is expected to pass
  /// the current user's own branch id(s) — see ProductFormScreen, which
  /// reads them from the existing AuthenticatedUser.branches rather than
  /// this repository inventing new branch infrastructure.
  Future<ManagedProduct> createProduct(
    ManagedProduct product, {
    List<int> branchIds = const [],
    XFile? imageFile,
  });

  /// PATCH /api/v1/products/{id} with the full product representation.
  /// Deliberately does NOT touch branch assignment — editing an existing
  /// product must not silently reassign or clear whatever branches it
  /// already has.
  Future<ManagedProduct> updateProduct(
    int id,
    ManagedProduct product, {
    XFile? imageFile,
  });

  /// PATCH /api/v1/products/{id} with only `is_active` — deliberately a
  /// minimal payload rather than routing through updateProduct(), for two
  /// reasons: (1) disabling is triggered from the Products list, which
  /// only has catalog-shaped data (no true base_price/variant deltas) —
  /// resending a full ManagedProduct reconstructed from that would risk
  /// silently overwriting fields with approximated values; (2) the
  /// backend's `sometimes` validation already treats an absent field as
  /// "don't touch it", so this is the correct minimal request for a
  /// single-flag toggle, not a shortcut.
  Future<List<RecipeItem>> getRecipe({required int productId, int? branchId});

  Future<List<RecipeItem>> updateRecipe({
    required int productId,
    required List<RecipeItem> items,
    int? branchId,
  });
  Future<void> setProductActive(int id, bool isActive);
}

class ApiProductsRepository implements ProductsRepository {
  ApiProductsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PosCategory>> getCategories({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/categories',
        queryParameters: {if (branchId != null) 'branch_id': branchId},
      ),
    );
    final data = response.data['data'] as List;
    return data
        .map((json) => PosCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PosCategory> createCategory({
    required int branchId,
    required String name,
    int sortOrder = 0,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.post(
        '/categories',
        data: {
          'branch_id': branchId,
          'name': name,
          'sort_order': sortOrder,
          'is_active': true,
        },
      ),
    );

    return PosCategory.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<PosCategory> updateCategory({
    required int categoryId,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.patch(
        '/categories/$categoryId',
        data: {
          if (name != null) 'name': name,
          if (sortOrder != null) 'sort_order': sortOrder,
          if (isActive != null) 'is_active': isActive,
        },
      ),
    );

    return PosCategory.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteCategory({required int categoryId}) async {
    await _apiClient.request((dio) => dio.delete('/categories/$categoryId'));
  }

  @override
  Future<List<PosProduct>> getProducts({int? branchId}) async {
    // Fetched once, unfiltered by category/search — category selection
    // and search both filter this list locally (see ProductsController),
    // matching the same "don't re-fetch per tap/keystroke" approach
    // already established by PosCatalogController for the same reason:
    // the backend has no search parameter, and re-fetching per category
    // tap isn't necessary when the full catalog is already in memory.
    // branch_id is a separate, orthogonal concern from that decision.
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/products',
        queryParameters: {if (branchId != null) 'branch_id': branchId},
      ),
    );
    final data = response.data['data'] as List;
    return data
        .map((json) => PosProduct.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ManagedProduct> createProduct(
    ManagedProduct product, {
    List<int> branchIds = const [],
    XFile? imageFile,
  }) async {
    final payload = product.toJson();
    if (branchIds.isNotEmpty) {
      payload['branches'] = branchIds
          .map((branchId) => {'branch_id': branchId, 'is_available': true})
          .toList();
    }

    final response = await _apiClient.request((dio) async {
      if (imageFile == null) {
        return dio.post('/products', data: payload);
      }

      final formData = await _photoForm(payload, imageFile);

      return dio.post('/products', data: formData);
    });
    return ManagedProduct.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<ManagedProduct> updateProduct(
    int id,
    ManagedProduct product, {
    XFile? imageFile,
  }) async {
    final response = await _apiClient.request((dio) async {
      if (imageFile == null) {
        return dio.patch('/products/$id', data: product.toJson());
      }

      final formData = await _photoForm(
        product.toJson(),
        imageFile,
        patch: true,
      );

      return dio.post('/products/$id', data: formData);
    });
    return ManagedProduct.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<FormData> _photoForm(
    Map<String, dynamic> payload,
    XFile image, {
    bool patch = false,
  }) async {
    final form = FormData();
    void add(String key, dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          add('$key[${entry.key}]', entry.value);
        }
      } else if (value is List) {
        // Empty arrays are omitted: product updates upsert variants and retain
        // omitted variants; an empty array does not delete historical records.
        for (var index = 0; index < value.length; index++) {
          add('$key[$index]', value[index]);
        }
      } else {
        form.fields.add(
          MapEntry(
            key,
            value is bool ? (value ? '1' : '0') : value?.toString() ?? '',
          ),
        );
      }
    }

    payload.forEach(add);
    if (patch) form.fields.add(const MapEntry('_method', 'PATCH'));
    form.files.add(
      MapEntry(
        'image',
        await MultipartFile.fromFile(image.path, filename: image.name),
      ),
    );
    return form;
  }

  @override
  Future<List<RecipeItem>> getRecipe({
    required int productId,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.get(
        '/products/$productId/recipe',
        queryParameters: {if (branchId != null) 'branch_id': branchId},
      ),
    );

    final data = response.data['data'] as Map<String, dynamic>;
    final items = data['items'] as List;

    return items
        .map((json) => RecipeItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<RecipeItem>> updateRecipe({
    required int productId,
    required List<RecipeItem> items,
    int? branchId,
  }) async {
    final response = await _apiClient.request(
      (dio) => dio.put(
        '/products/$productId/recipe',
        data: {
          if (branchId != null) 'branch_id': branchId,
          'items': items.map((item) => item.toJson()).toList(),
        },
      ),
    );

    final data = response.data['data'] as Map<String, dynamic>;
    final updatedItems = data['items'] as List;

    return updatedItems
        .map((json) => RecipeItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> setProductActive(int id, bool isActive) async {
    await _apiClient.request(
      (dio) => dio.patch('/products/$id', data: {'is_active': isActive}),
    );
  }
}

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ApiProductsRepository(ref.watch(apiClientProvider));
});
