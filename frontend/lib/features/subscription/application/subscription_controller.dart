import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/subscription_repository.dart';
import 'subscription_state.dart';

/// Loads and refreshes the authenticated business subscription.
class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController(this._repository)
      : super(const SubscriptionLoading()) {
    _initialization = _load();
  }

  final SubscriptionRepository _repository;

  late Future<void> _initialization;

  Future<void> get initialization => _initialization;

  /// Reloads the current business subscription.
  Future<void> refresh() {
    final future = _load();
    _initialization = future;
    return future;
  }

  Future<void> _load() async {
    if (!mounted) return;

    state = const SubscriptionLoading();

    try {
      final subscription = await _repository.getSubscription();

      if (!mounted) return;

      state = SubscriptionLoaded(
        subscription: subscription,
      );
    } catch (e) {
      if (!mounted) return;

      state = SubscriptionError(
        e is ApiException ? e.message : 'Something went wrong',
      );
    }
  }
}

final subscriptionControllerProvider = StateNotifierProvider.autoDispose<
    SubscriptionController, SubscriptionState>((ref) {
  return SubscriptionController(
    ref.watch(subscriptionRepositoryProvider),
  );
});
