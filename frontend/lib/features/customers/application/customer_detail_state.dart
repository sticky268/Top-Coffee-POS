import '../domain/customer_models.dart';

sealed class CustomerDetailState {
  const CustomerDetailState();
}

class CustomerDetailLoading extends CustomerDetailState {
  const CustomerDetailLoading();
}

class CustomerDetailLoaded extends CustomerDetailState {
  const CustomerDetailLoaded({
    required this.customer,
  });

  final Customer customer;
}

class CustomerDetailError extends CustomerDetailState {
  const CustomerDetailError(this.message);

  final String message;
}
