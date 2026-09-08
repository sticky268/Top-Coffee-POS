import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/branch/current_branch_provider.dart';

import '../data/pos_repository.dart';
import '../domain/pos_models.dart';
import 'checkout_state.dart';

/// Submits the cart as a real order. Unlike PosCatalogController/
/// AuthController, this controller does no work at construction time (no
/// auto-fetch), so it doesn't need the `initialization`-future pattern —
/// submission only happens on an explicit user action (Confirm Payment).
/// `mounted` guards are still applied around the one `await`, for the same
/// disposal-safety reason as elsewhere.
///
/// autoDispose: a fresh CheckoutController per visit to the checkout
/// screen, so a previous success/error doesn't linger into the next order.
class CheckoutController extends StateNotifier<CheckoutState> {
  CheckoutController(this._repository, this._ref) : super(const CheckoutIdle());

  final PosRepository _repository;
  final Ref _ref;

  Future<void> submit({
    required List<CartItem> items,
    required String paymentMethod,
    double? tendered,
    required double discountTotal,
  }) async {
    if (!mounted) return;
    state = const CheckoutSubmitting();

    try {
      final confirmation = await _repository.createOrder(
        items: items,
        paymentMethod: paymentMethod,
        tendered: tendered,
        discountTotal: discountTotal,
        branchId: _ref.read(currentBranchProvider)?.id,
      );
      if (!mounted) return;
      state = CheckoutSuccess(confirmation);
    } catch (e) {
      if (!mounted) return;
      state =
          CheckoutError(e is ApiException ? e.message : 'Something went wrong');
    }
  }
}

final checkoutControllerProvider =
    StateNotifierProvider.autoDispose<CheckoutController, CheckoutState>((ref) {
  return CheckoutController(
    ref.watch(posRepositoryProvider),
    ref,
  );
});
