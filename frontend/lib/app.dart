import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/offline/order_sync.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/application/auth_state.dart';
import 'features/subscription/application/subscription_controller.dart';

class TopCoffeeApp extends ConsumerWidget {
  const TopCoffeeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final auth = ref.watch(authControllerProvider);

    // Load subscription details only after authentication succeeds.
    // Subscription state remains separate from AuthState.
    if (auth is AuthAuthenticated) {
      ref.watch(subscriptionControllerProvider);
      ref.watch(orderSyncWorkerProvider);
    }

    return MaterialApp.router(
      title: 'Top Coffee POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
