import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import 'dashboard_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart' as pos_ui;

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
                      onPressed: () {
                        // The rail may disappear during rotation while the sheet
                        // stays open. Keep the router, not a disposable context.
                        final router = GoRouter.of(context);
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (sheetContext) => SizedBox(
                            height:
                                MediaQuery.sizeOf(sheetContext).height * .85,
                            child: DashboardNavigation(
                              selectedRoute: '/home',
                              onDestinationSelected: (route) {
                                Navigator.of(sheetContext).pop();
                                router.go(route);
                              },
                            ),
                          ),
                        );
                      }),
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
                      Tooltip(
                        message: destination.$1,
                        child: Semantics(
                          selected: destination.$3 == '/home',
                          child: pos_ui.ActionSurface(
                            key: ValueKey('home-nav-${destination.$1}'),
                            onTap: () => context.go(destination.$3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              child: Column(children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: destination.$3 == '/home'
                                        ? AppColors.caramel
                                        : null,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(destination.$2,
                                      color: destination.$3 == '/home'
                                          ? AppColors.espresso
                                          : AppColors.cream),
                                ),
                                const SizedBox(height: 4),
                                Text(destination.$1,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: AppColors.cream)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                ]),
              ))),
    );
  }
}
