import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pos_models.dart';
import 'cart_state.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';

/// Manages the in-progress order's cart. Deliberately separate from
/// PosCatalogController's loading/loaded/error lifecycle (Part 4's "keep
/// cart state separate from catalog loading state") — the cart must
/// survive a catalog reload/error/retry untouched.
class CartController extends StateNotifier<CartState> {
  CartController([super.state = const CartState()]);

  /// Adds one unit of [product] (with [variant] if selected). If a line
  /// for this exact product+variant combination already exists, its
  /// quantity is increased instead of creating a duplicate line — matching
  /// on CartItem.lineKey, which is why a "Latte — Medium" line and a
  /// "Latte — Large" line never merge into each other.
  void addItem(
    PosProduct product, {
    PosProductVariant? variant,
    List<int> modifierIds = const [],
    List<int> comboSelections = const [],
    int extraCents = 0,
    String configurationLabel = '',
  }) {
    final newItem = CartItem(
      product: product,
      variant: variant,
      quantity: 1,
      modifierIds: modifierIds,
      comboSelections: comboSelections,
      extraCents: extraCents,
      configurationLabel: configurationLabel,
    );
    final existingIndex = state.items.indexWhere(
      (i) => i.lineKey == newItem.lineKey,
    );

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
    state = state.copyWith(
      items: state.items.where((i) => i.lineKey != lineKey).toList(),
    );
  }

  /// Manually set a flat discount amount. Clamped to be non-negative here;
  /// CartState.total additionally clamps the *result* so a discount
  /// larger than the subtotal can never produce a negative total.
  void setDiscount(double amount) {
    state = state.copyWith(
      discountTotal: amount < 0 ? 0 : amount,
      clearMenuDiscount: true,
    );
  }

  void selectMenuDiscount(Map<String, dynamic>? offer) => state =
      state.copyWith(menuDiscount: offer, clearMenuDiscount: offer == null);

  void selectTable(PosTable? table) =>
      state = state.copyWith(table: table, clearTable: table == null);

  /// Empties the cart entirely, including any manually-set discount —
  /// this is the "Clear Cart" action.
  void clear() => state = const CartState();
}

final _draftsProvider = Provider((ref) => <String, CartState>{});

final cartControllerProvider = StateNotifierProvider<CartController, CartState>(
  (ref) {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => auth is AuthAuthenticated ? auth.user.id : null,
      ),
    );
    final branchId = ref.watch(
      currentBranchProvider.select((branch) => branch?.id),
    );
    final drafts = ref.read(_draftsProvider);
    final key = '$userId:$branchId';
    final controller = CartController(drafts[key] ?? const CartState());
    controller.addListener((state) => drafts[key] = state);
    return controller;
  },
);
