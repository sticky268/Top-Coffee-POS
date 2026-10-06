import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/branch/current_branch_provider.dart';

import '../data/pos_repository.dart';
import '../domain/pos_models.dart';
import 'checkout_state.dart';

/// Submits the cart as a real order. Unlike PosCatalogController/
/// AuthController, this controller does no work at construction time (no
/// auto-fetch), so it doesn't need the `initialization`-future pattern â€”
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

  // Survives checkout screen disposal after a network timeout. Cleared only
  // after the server confirms creation. Different payloads use different IDs.
  static final Map<String, String> _pendingRequests = {};
  static const Uuid _uuid = Uuid();

  Future<void> submit({
    required List<CartItem> items,
    required String paymentMethod,
    required String orderType,
    int? tableId,
    double? tendered,
    List<Map<String, dynamic>>? splitPayments,
    required double discountTotal,
    int? customerId,
  }) async {
    // Prevent concurrent requests and accidental resubmission after success.
    if (!mounted ||
        state is CheckoutSubmitting ||
        state is CheckoutSuccess ||
        state is CheckoutHeld) {
      return;
    }
    final branchId = _ref.read(currentBranchProvider)?.id;
    final requestKey = jsonEncode([
      'checkout', branchId, customerId, orderType, tableId, discountTotal,
      paymentMethod, tendered, splitPayments,
      for (final item in items)
        [item.product.id, item.variant?.id, item.quantity],
    ]);
    final requestUuid = _pendingRequests.putIfAbsent(requestKey, _uuid.v4);
    state = const CheckoutSubmitting();

    try {
      final confirmation = await _repository.createOrder(
        requestUuid: requestUuid,
        items: items,
        paymentMethod: paymentMethod,
        orderType: orderType,
        tableId: tableId,
        tendered: tendered,
        splitPayments: splitPayments,
        discountTotal: discountTotal,
        customerId: customerId,
        branchId: branchId,
      );
      _pendingRequests.remove(requestKey);
      if (!mounted) return;
      state = CheckoutSuccess(confirmation);
    } catch (e) {
      if (!mounted) return;
      state =
          CheckoutError(e is ApiException ? e.message : 'Something went wrong');
    }
  }

  Future<void> hold({
    required List<CartItem> items,
    required String orderType,
    required int tableId,
    required double discountTotal,
    int? customerId,
  }) async {
    // Prevent concurrent requests and accidental resubmission after success.
    if (!mounted ||
        state is CheckoutSubmitting ||
        state is CheckoutSuccess ||
        state is CheckoutHeld) {
      return;
    }
    final branchId = _ref.read(currentBranchProvider)?.id;
    final requestKey = jsonEncode([
      'hold', branchId, customerId, orderType, tableId, discountTotal,
      for (final item in items)
        [item.product.id, item.variant?.id, item.quantity],
    ]);
    final requestUuid = _pendingRequests.putIfAbsent(requestKey, _uuid.v4);
    state = const CheckoutSubmitting();

    try {
      final confirmation = await _repository.holdOrder(
        requestUuid: requestUuid,
        items: items,
        orderType: orderType,
        tableId: tableId,
        discountTotal: discountTotal,
        customerId: customerId,
        branchId: branchId,
      );

      _pendingRequests.remove(requestKey);
      if (!mounted) return;
      state = CheckoutHeld(confirmation);
    } catch (e) {
      if (!mounted) return;
      state = CheckoutError(
        e is ApiException ? e.message : 'Something went wrong',
      );
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
