import '../domain/subscription_models.dart';

sealed class SubscriptionState {
  const SubscriptionState();
}

class SubscriptionLoading extends SubscriptionState {
  const SubscriptionLoading();
}

class SubscriptionLoaded extends SubscriptionState {
  const SubscriptionLoaded({
    required this.subscription,
  });

  final SubscriptionDetails subscription;

  bool get canModify => subscription.canModify;

  bool get isReadOnly => subscription.isReadOnly;

  bool get isExpired => subscription.isExpired;

  bool get isSuspended => subscription.isSuspended;
}

class SubscriptionError extends SubscriptionState {
  const SubscriptionError(this.message);

  final String message;
}
