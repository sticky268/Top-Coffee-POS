import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pos_models.dart';
import 'cart_state.dart';

/// Manages the in-progress order's cart. Deliberately separate from
/// PosCatalogController's loading/loaded/error lifecycle (Part 4's "keep
/// cart state separate from catalog loading state") — the cart must
/// survive a catalog reload/error/retry untouched.
class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  /// Adds one unit of [product] (with [variant] if selected). If a line
  /// for this exact product+variant combination already exists, its
  /// quantity is increased instead of creating a duplicate line — matching
  /// on CartItem.lineKey, which is why a "Latte — Medium" line and a
  /// "Latte — Large" line never merge into each other.
  void addItem(PosProduct product, {PosProductVariant? variant}) {
    final newItem = CartItem(product: product, variant: variant, quantity: 1);
    final existingIndex = state.items.indexWhere((i) => i.lineKey == newItem.lineKey);

    if (existingIndex == -1) {
      state = state.copyWith(items: [...state.items, newItem]);
      return;
    }

    final updated = [...state.items];
    updated[existingIndex] = updated[existingIndex].copyWith(
      quantity: updated[existingIndex].quantity + 1,
    );
    state = state.copyWith(items: updated);
  }

  void incrementQuantity(String lineKey) => _adjustQuantity(lineKey, 1);

  /// Decrementing to 0 removes the line — this is what satisfies "remove
  /// item" for the common case; removeItem() below covers removing a line
  /// outright regardless of its current quantity.
  void decrementQuantity(String lineKey) => _adjustQuantity(lineKey, -1);

  void _adjustQuantity(String lineKey, int delta) {
    final index = state.items.indexWhere((i) => i.lineKey == lineKey);
    if (index == -1) return;

    final newQuantity = state.items[index].quantity + delta;
    if (newQuantity <= 0) {
      removeItem(lineKey);
      return;
    }

    final updated = [...state.items];
    updated[index] = updated[index].copyWith(quantity: newQuantity);
    state = state.copyWith(items: updated);
  }

  void removeItem(String lineKey) {
    state = state.copyWith(items: state.items.where((i) => i.lineKey != lineKey).toList());
  }

  /// Manually set a flat discount amount. Clamped to be non-negative here;
  /// CartState.total additionally clamps the *result* so a discount
  /// larger than the subtotal can never produce a negative total.
  void setDiscount(double amount) {
    state = state.copyWith(discountTotal: amount < 0 ? 0 : amount);
  }

  /// Empties the cart entirely, including any manually-set discount —
  /// this is the "Clear Cart" action.
  void clear() => state = const CartState();
}

final cartControllerProvider = StateNotifierProvider<CartController, CartState>((ref) {
  return CartController();
});
