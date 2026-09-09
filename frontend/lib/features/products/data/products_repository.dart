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
  Future<void> setProductActive(int id, bool isActive);
}

class ApiProductsRepository implements ProductsRepository {
  ApiProductsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PosCategory>> getCategories({int? branchId}) async {
    final response = await _apiClient.request(
      (dio) => dio.get('/categories', queryParameters: {
        if (branchId != null) 'branch_id': branchId,
      }),
    );
    final data = response.data['data'] as List;
    return data.map((json) => PosCategory.fromJson(json as Map<String, dynamic>)).toList();
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

  return PosCategory.fromJson(
    response.data['data'] as Map<String, dynamic>,
  );
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
      (dio) => dio.get('/products', queryParameters: {
        if (branchId != null) 'branch_id': branchId,
      }),
    );
    final data = response.data['data'] as List;
    return data.map((json) => PosProduct.fromJson(json as Map<String, dynamic>)).toList();
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

final response = await _apiClient.request(
  (dio) async {
    if (imageFile == null) {
      return dio.post('/products', data: payload);
    }

    final formData = FormData();

    payload.forEach((key, value) {
      if (key == 'variants' && value is List) {
        for (var i = 0; i < value.length; i++) {
          final variant = value[i] as Map<String, dynamic>;

          variant.forEach((variantKey, variantValue) {
            formData.fields.add(
              MapEntry(
                'variants[$i][$variantKey]',
                variantValue?.toString() ?? '',
              ),
            );
          });
        }
      } else if (key == 'branches' && value is List) {
        for (var i = 0; i < value.length; i++) {
          final branch = value[i] as Map<String, dynamic>;

          branch.forEach((branchKey, branchValue) {
            formData.fields.add(
              MapEntry(
                'branches[$i][$branchKey]',
                branchValue?.toString() ?? '',
              ),
            );
          });
        }
      } else {
        formData.fields.add(
          MapEntry(key, value?.toString() ?? ''),
        );
      }
    });

    formData.files.add(
      MapEntry(
        'image',
        await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.name,
        ),
      ),
    );

    return dio.post('/products', data: formData);
  },
);
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
final response = await _apiClient.request(
  (dio) async {
    if (imageFile == null) {
      return dio.patch('/products/$id', data: product.toJson());
    }

    final formData = FormData();
    final payload = product.toJson();

    payload.forEach((key, value) {
      formData.fields.add(
        MapEntry(key, value?.toString() ?? ''),
      );
    });

    formData.fields.add(
      const MapEntry('_method', 'PATCH'),
    );

    formData.files.add(
      MapEntry(
        'image',
        await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.name,
        ),
      ),
    );

    return dio.post('/products/$id', data: formData);
  },
);
    return ManagedProduct.fromJson(response.data['data'] as Map<String, dynamic>);
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
