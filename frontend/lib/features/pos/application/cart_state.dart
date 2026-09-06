import '../domain/pos_models.dart';

/// The in-progress order's cart. Deliberately a plain immutable data class
/// (not a sealed loading/loaded/error state like PosCatalogState) — the
/// cart has no "loading" concept, it's pure local state mutated by user
/// actions, so that machinery would be unnecessary here.
class CartState {
  const CartState({this.items = const [], this.discountTotal = 0});

  final List<CartItem> items;

  /// Flat dollar amount, manually set by the cashier — no percentage
  /// tiers, coupon codes, or eligibility rules yet (deliberately simple
  /// per the task's "prepare the UI/state for it, but don't add
  /// complicated discount rules yet"). Clamped against subtotal so total
  /// can never go negative — see [total].
  final double discountTotal;

  bool get isEmpty => items.isEmpty;

  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get total {
    final result = subtotal - discountTotal;
    return result < 0 ? 0 : result;
  }

  CartState copyWith({List<CartItem>? items, double? discountTotal}) {
    return CartState(
      items: items ?? this.items,
      discountTotal: discountTotal ?? this.discountTotal,
    );
  }
}
