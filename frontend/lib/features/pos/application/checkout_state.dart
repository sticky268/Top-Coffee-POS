import '../domain/pos_models.dart';

sealed class CheckoutState {
  const CheckoutState();
}

/// Nothing submitted yet â€” the payment form is interactive.
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

class CheckoutHeld extends CheckoutState {
  const CheckoutHeld(this.confirmation);
  final OrderConfirmation confirmation;
}

/// Durably saved locally, with no claim that the server accepted payment.
class CheckoutQueued extends CheckoutState {
  const CheckoutQueued(this.uuid);
  final String uuid;
}

/// Distinct from Idle so the screen can show an error banner while still
/// letting the cashier retry with the same cart â€” a failed checkout must
/// never lose the cart contents.
class CheckoutError extends CheckoutState {
  const CheckoutError(this.message);
  final String message;
}
