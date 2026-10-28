import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/pos/data/pos_repository.dart';

import '../../features/dashboard/presentation/widgets/dashboard_navigation.dart';
import '../widgets/page_app_bar.dart';
import '../theme/app_colors.dart';
import '../theme/coffee_studio_theme.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.selectedRoute});

  final Widget child;
  final String selectedRoute;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _drawerKey = GlobalKey<ScaffoldState>();
  String? _pendingRoute;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedRoute != widget.selectedRoute) _pendingRoute = null;
  }

  void _selectDrawerDestination(String route) {
    // Keep destination initialization out of the drawer's closing animation.
    // Repeated taps retain only the latest choice.
    _pendingRoute = route == widget.selectedRoute ? null : route;
    _drawerKey.currentState?.closeDrawer();
  }

  void _drawerChanged(bool isOpen) {
    if (isOpen) _pendingRoute = null;
  }

  void _drawerContentsRemoved() {
    final route = _pendingRoute;
    final source = widget.selectedRoute;
    if (route == null) return;
    // The drawer contents unmount only when its closing animation finishes.
    // Navigate after that tree update, rather than during disposal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _pendingRoute != route ||
          widget.selectedRoute != source ||
          (_drawerKey.currentState?.isDrawerOpen ?? false)) {
        return;
      }
      _pendingRoute = null;
      context.go(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.selectedRoute == '/home';
    final studio = CoffeeStudioTheme.active(context);
    final counter = home;
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
        Expanded(child: widget.child),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop || (counter && !studio)) {
          return Scaffold(
            key: _drawerKey,
            onDrawerChanged: _drawerChanged,
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
              child: _DrawerContents(
                  onRemoved: _drawerContentsRemoved,
                  child: DashboardNavigation(
                      selectedRoute: widget.selectedRoute,
                      onDestinationSelected: _selectDrawerDestination)),
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
              DashboardNavigation(
                selectedRoute: widget.selectedRoute,
                compact: studio &&
                    !home &&
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

/// Its lifetime follows the actual drawer animation, including reduced motion.
class _DrawerContents extends StatefulWidget {
  const _DrawerContents({required this.onRemoved, required this.child});
  final VoidCallback onRemoved;
  final Widget child;

  @override
  State<_DrawerContents> createState() => _DrawerContentsState();
}

class _DrawerContentsState extends State<_DrawerContents> {
  @override
  void dispose() {
    widget.onRemoved();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
