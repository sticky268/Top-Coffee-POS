import '../domain/pos_models.dart';

sealed class CheckoutState {
  const CheckoutState();
}

/// Nothing submitted yet — the payment form is interactive.
class CheckoutIdle extends CheckoutState {
  const CheckoutIdle();
}

class CheckoutSubmitting extends CheckoutState {
  const CheckoutSubmitting();
}

class CheckoutSuccess extends CheckoutState {
  const CheckoutSuccess(this.confirmation);
  final OrderConfirmation confirmation;
}

/// Distinct from Idle so the screen can show an error banner while still
/// letting the cashier retry with the same cart — a failed checkout must
/// never lose the cart contents.
class CheckoutError extends CheckoutState {
  const CheckoutError(this.message);
  final String message;
}
