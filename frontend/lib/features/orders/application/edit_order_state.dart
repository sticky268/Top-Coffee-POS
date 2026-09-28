import '../../pos/domain/pos_models.dart';

class EditOrderState {
  const EditOrderState({
    this.items = const [],
    this.discountTotal = 0,
    this.isSaving = false,
    this.errorMessage,
  });

  final List<CartItem> items;
  final double discountTotal;
  final bool isSaving;
  final String? errorMessage;

  bool get isEmpty => items.isEmpty;

  int get totalItemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get total {
    final result = subtotal - discountTotal;
    return result < 0 ? 0 : result;
  }

  EditOrderState copyWith({
    List<CartItem>? items,
    double? discountTotal,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return EditOrderState(
      items: items ?? this.items,
      discountTotal: discountTotal ?? this.discountTotal,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
