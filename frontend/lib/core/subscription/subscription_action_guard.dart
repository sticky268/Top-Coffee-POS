import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/subscription/application/subscription_controller.dart';
import '../../features/subscription/application/subscription_state.dart';

/// Provides the current subscription write-access state to UI actions.
///
/// The backend remains the source of truth. This guard is only a UX
/// layer that prevents users from starting write actions when the
/// subscription is expired or suspended.
class SubscriptionActionGuard {
  const SubscriptionActionGuard._();

  static bool canModify(WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);

    return state is SubscriptionLoaded && state.canModify;
  }

  static bool isReadOnly(WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);

    return state is SubscriptionLoaded && state.isReadOnly;
  }
}
