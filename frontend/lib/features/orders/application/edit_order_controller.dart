import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';

import '../../pos/domain/pos_models.dart';
import '../../pos/application/pos_catalog_controller.dart';
import '../../pos/application/pos_catalog_state.dart';
import '../data/orders_repository.dart';
import '../domain/order_models.dart';
import 'edit_order_state.dart';

class EditOrderController extends StateNotifier<EditOrderState> {
  EditOrderController(
    this._repository,
    this._catalog,
    this._order,
  ) : super(const EditOrderState()) {
    _initialize();
  }

  final OrdersRepository _repository;
  final PosCatalogState _catalog;
  final OrderDetail _order;

  void _initialize() {
    final catalogProducts =
        _catalog is PosCatalogLoaded ? _catalog.products : const <PosProduct>[];

    final items = <CartItem>[];

    for (final orderItem in _order.items) {
      final product = _findProduct(catalogProducts, orderItem.productId);

      if (product == null) {
        continue;
      }

      PosProductVariant? variant;

      if (orderItem.productVariantId != null) {
        for (final candidate in product.variants) {
          if (candidate.id == orderItem.productVariantId) {
            variant = candidate;
            break;
          }
        }
      }

      items.add(
        CartItem(
          product: product,
          variant: variant,
          quantity: orderItem.quantity,
        ),
      );
    }

    state = EditOrderState(
      items: items,
      discountTotal: _order.discountTotal.toDouble(),
    );
  }

  PosProduct? _findProduct(List<PosProduct> products, int productId) {
    for (final product in products) {
      if (product.id == productId) {
        return product;
      }
    }

    return null;
  }

  void addItem(
    PosProduct product, {
    PosProductVariant? variant,
  }) {
    final lineKey = '${product.id}:${variant?.id ?? 'base'}';

    final existingIndex =
        state.items.indexWhere((item) => item.lineKey == lineKey);

    if (existingIndex >= 0) {
      final updatedItems = [...state.items];
      final existing = updatedItems[existingIndex];

      updatedItems[existingIndex] =
          existing.copyWith(quantity: existing.quantity + 1);

      state = state.copyWith(
        items: updatedItems,
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      items: [
        ...state.items,
        CartItem(
          product: product,
          variant: variant,
          quantity: 1,
        ),
      ],
      clearError: true,
    );
  }

  void incrementQuantity(String lineKey) {
    _adjustQuantity(lineKey, 1);
  }

  void decrementQuantity(String lineKey) {
    _adjustQuantity(lineKey, -1);
  }

  void _adjustQuantity(String lineKey, int delta) {
    final index = state.items.indexWhere((item) => item.lineKey == lineKey);

    if (index < 0) {
      return;
    }

    final updatedItems = [...state.items];
    final item = updatedItems[index];
    final nextQuantity = item.quantity + delta;

    if (nextQuantity <= 0) {
      updatedItems.removeAt(index);
    } else {
      updatedItems[index] = item.copyWith(quantity: nextQuantity);
    }

    state = state.copyWith(
      items: updatedItems,
      clearError: true,
    );
  }

  void removeItem(String lineKey) {
    state = state.copyWith(
      items: state.items.where((item) => item.lineKey != lineKey).toList(),
      clearError: true,
    );
  }

  void clear() {
    state = state.copyWith(
      items: const [],
      clearError: true,
    );
  }

  void setDiscount(double amount) {
    final normalized = amount < 0 ? 0.0 : amount;

    state = state.copyWith(
      discountTotal: normalized,
      clearError: true,
    );
  }

  Future<OrderDetail?> save({
    int? branchId,
  }) async {
    if (state.isSaving) {
      return null;
    }

    if (state.items.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Order must contain at least one item.',
      );
      return null;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
    );

    try {
      final items = state.items
          .map(
            (item) => {
              'product_id': item.product.id,
              if (item.variant != null) 'product_variant_id': item.variant!.id,
              'quantity': item.quantity,
            },
          )
          .toList();

      final updatedOrder = await _repository.updateOrder(
        orderId: _order.id,
        items: items,
        discountTotal: state.discountTotal,
        branchId: branchId,
      );

      if (!mounted) {
        return updatedOrder;
      }

      state = state.copyWith(
        isSaving: false,
        clearError: true,
      );

      return updatedOrder;
    } catch (e) {
      if (!mounted) {
        return null;
      }

      String errorMessage;

      if (e is ValidationException) {
        final details = <String>[];

        for (final entry in e.errors.entries) {
          final value = entry.value;

          if (value is List) {
            details.addAll(
              value.map((item) => item.toString()),
            );
          } else {
            details.add('${entry.key}: $value');
          }
        }

        errorMessage =
            details.isEmpty ? e.message : '${e.message}: ${details.join(' ')}';
      } else if (e is ApiException) {
        errorMessage = e.message;
      } else {
        errorMessage = e.toString();
      }

      state = state.copyWith(
        isSaving: false,
        errorMessage: errorMessage,
      );

      return null;
    }
  }
}

final editOrderControllerProvider = StateNotifierProvider.autoDispose
    .family<EditOrderController, EditOrderState, OrderDetail>(
  (ref, order) {
    final catalog = ref.watch(posCatalogControllerProvider);

    return EditOrderController(
      ref.watch(ordersRepositoryProvider),
      catalog,
      order,
    );
  },
);
