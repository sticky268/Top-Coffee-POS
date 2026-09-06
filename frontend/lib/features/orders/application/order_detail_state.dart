import '../domain/order_models.dart';

sealed class OrderDetailState {
  const OrderDetailState();
}

class OrderDetailLoading extends OrderDetailState {
  const OrderDetailLoading();
}

class OrderDetailLoaded extends OrderDetailState {
  const OrderDetailLoaded(this.order);
  final OrderDetail order;
}

class OrderDetailError extends OrderDetailState {
  const OrderDetailError(this.message);
  final String message;
}
