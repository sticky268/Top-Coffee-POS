import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import 'dashboard_navigation.dart';
import '../../../../core/theme/app_colors.dart';

/// The modern home keeps frequent destinations close; the full menu remains
/// available so changing layout never removes less-frequent destinations.
class HomeNavigationRail extends ConsumerWidget {
  const HomeNavigationRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    bool allowed(String permission) =>
        auth is AuthAuthenticated && auth.user.hasPermission(permission);
    return Material(
      color: AppColors.espresso,
      child: SafeArea(
          child: SizedBox(
              width: 96,
              child: SingleChildScrollView(
                child: Column(children: [
                  const SizedBox(height: 12),
                  IconButton(
                      tooltip: 'All tools',
                      icon: const Icon(Icons.menu, color: AppColors.white),
                      onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (sheetContext) => SizedBox(
                                height: MediaQuery.sizeOf(context).height * .85,
                                child: DashboardNavigation(
                                    selectedRoute: '/home',
                                    onDestinationSelected: (route) {
                                      Navigator.of(sheetContext).pop();
                                      context.go(route);
                                    })),
                          )),
                  for (final destination in [
                    ('Home', Icons.home_outlined, '/home', true),
                    (
                      'POS',
                      Icons.point_of_sale_outlined,
                      '/pos/select-table',
                      allowed('orders.create')
                    ),
                    (
                      'Orders',
                      Icons.receipt_long_outlined,
                      '/orders',
                      allowed('orders.view')
                    ),
                    (
                      'Menu',
                      Icons.restaurant_menu_outlined,
                      '/manage-menu',
                      allowed('products.manage')
                    ),
                    (
                      'Inventory',
                      Icons.inventory_2_outlined,
                      '/inventory',
                      allowed('inventory.view')
                    ),
                    (
                      'Reports',
                      Icons.bar_chart_outlined,
                      '/reports',
                      allowed('reports.view')
                    ),
                    ('Settings', Icons.settings_outlined, '/settings', true),
                  ])
                    if (destination.$4)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(children: [
                            IconButton(
                                tooltip: destination.$1,
                                isSelected: destination.$3 == '/home',
                                style: IconButton.styleFrom(
                                    backgroundColor: destination.$3 == '/home'
                                        ? AppColors.caramel
                                        : null),
                                icon: Icon(destination.$2,
                                    color: destination.$3 == '/home'
                                        ? AppColors.espresso
                                        : AppColors.cream),
                                onPressed: () => context.go(destination.$3)),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(destination.$1,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: AppColors.cream))),
                          ])),
                ]),
              ))),
    );
  }
}
