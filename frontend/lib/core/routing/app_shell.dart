import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/pos/data/pos_repository.dart';

import '../../features/dashboard/presentation/widgets/dashboard_navigation.dart';
import '../widgets/page_app_bar.dart';
import '../theme/home_layout_preference.dart';
import '../theme/app_colors.dart';
import '../theme/coffee_studio_theme.dart';
import '../../features/dashboard/presentation/widgets/home_navigation_rail.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.selectedRoute});

  final Widget child;
  final String selectedRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final home = selectedRoute == '/home';
    final studio = CoffeeStudioTheme.active(context);
    final counter = home && layout == HomeLayout.coffeeCounter;
    final usingCache = ref.watch(cachedCatalogProvider);
    final content = Column(
      children: [
        if (usingCache)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Text(
              'Using saved catalog. Orders will wait for server confirmation if the connection is unavailable.',
            ),
          ),
        Expanded(child: child),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop || (counter && !studio)) {
          return Scaffold(
            // Dashboard has no page toolbar; all other routes provide one.
            appBar: home
                ? AppBar(
                    title: Text('Top Coffee POS',
                        style: counter
                            ? const TextStyle(color: AppColors.white)
                            : null),
                    backgroundColor: counter ? AppColors.espresso : null,
                    foregroundColor: counter ? AppColors.white : null,
                  )
                : null,
            drawer: Drawer(
              child: DashboardNavigation(selectedRoute: selectedRoute),
            ),
            body: Builder(
              builder: (shellContext) => PageNavigation(
                openMenu: () => Scaffold.of(shellContext).openDrawer(),
                child: SafeArea(
                  top: usingCache,
                  bottom: false,
                  left: false,
                  right: false,
                  child: content,
                ),
              ),
            ),
          );
        }

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (home &&
                  layout == HomeLayout.modern &&
                  !CoffeeStudioTheme.active(context))
                const HomeNavigationRail()
              else
                DashboardNavigation(
                  selectedRoute: selectedRoute,
                  compact: studio &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20,
                ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}
