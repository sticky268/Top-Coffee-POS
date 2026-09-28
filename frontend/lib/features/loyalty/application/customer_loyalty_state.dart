import '../domain/loyalty_models.dart';

sealed class CustomerLoyaltyState {
  const CustomerLoyaltyState();
}

class CustomerLoyaltyLoading extends CustomerLoyaltyState {
  const CustomerLoyaltyLoading();
}

class CustomerLoyaltyLoaded extends CustomerLoyaltyState {
  const CustomerLoyaltyLoaded({
    required this.loyalty,
  });

  final CustomerLoyalty loyalty;
}

class CustomerLoyaltyError extends CustomerLoyaltyState {
  const CustomerLoyaltyError(this.message);

  final String message;
}