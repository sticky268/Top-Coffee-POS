import '../domain/managed_product_models.dart';

sealed class ProductFormState {
  const ProductFormState();
}

/// Form is interactive, nothing submitted yet (or a previous save
/// finished and the user is editing again).
class ProductFormIdle extends ProductFormState {
  const ProductFormIdle();
}

class ProductFormSaving extends ProductFormState {
  const ProductFormSaving();
}

class ProductFormSuccess extends ProductFormState {
  const ProductFormSuccess(this.product);
  final ManagedProduct product;
}

/// Distinct from Idle so the screen can show an error banner while still
/// letting the user retry with their already-entered field values — a
/// failed save must never lose what they typed.
class ProductFormError extends ProductFormState {
  const ProductFormError(this.message);
  final String message;
}
