import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';

class DashboardNavigation extends StatelessWidget {
  const DashboardNavigation({super.key, required this.selectedRoute});

  final String selectedRoute;

  void _navigate(BuildContext context, String route) {
    if (selectedRoute == route) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
              child: Row(
                children: [
                  Icon(
                    Icons.local_cafe_rounded,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Top Coffee',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _NavigationSection(
                    title: 'MAIN',
                    children: [
                      _NavigationItem(
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard,
                        label: 'Dashboard',
                        route: '/home',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/home'),
                      ),
                      _NavigationItem(
                        icon: Icons.point_of_sale_outlined,
                        selectedIcon: Icons.point_of_sale,
                        label: 'POS',
                        route: '/pos/select-table',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/pos/select-table'),
                      ),
                      _NavigationItem(
                        icon: Icons.receipt_long_outlined,
                        selectedIcon: Icons.receipt_long,
                        label: 'Orders',
                        route: '/orders',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/orders'),
                      ),
                      _NavigationItem(
                        icon: Icons.soup_kitchen_outlined,
                        selectedIcon: Icons.soup_kitchen,
                        label: 'Kitchen Display',
                        route: '/kds',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/kds'),
                      ),
                    ],
                  ),
                  _NavigationSection(
                    title: 'CATALOG',
                    children: [
                      _NavigationItem(
                        icon: Icons.local_cafe_outlined,
                        selectedIcon: Icons.local_cafe,
                        label: 'Products',
                        route: '/products',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/products'),
                      ),
                      _NavigationItem(
                        icon: Icons.category_outlined,
                        selectedIcon: Icons.category,
                        label: 'Categories',
                        route: '/products/categories',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/products/categories'),
                      ),
                    ],
                  ),
                  _NavigationSection(
                    title: 'OPERATIONS',
                    children: [
                      _NavigationItem(
                        icon: Icons.inventory_2_outlined,
                        selectedIcon: Icons.inventory_2,
                        label: 'Inventory',
                        route: '/inventory',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/inventory'),
                      ),
                      _NavigationItem(
                        icon: Icons.table_restaurant_outlined,
                        selectedIcon: Icons.table_restaurant,
                        label: 'Tables',
                        route: '/tables',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/tables'),
                      ),
                      _NavigationItem(
                        icon: Icons.receipt_long_outlined,
                        selectedIcon: Icons.receipt_long,
                        label: 'Expenses',
                        route: '/expenses',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/expenses'),
                      ),
                      _NavigationItem(
                        icon: Icons.local_shipping_outlined,
                        selectedIcon: Icons.local_shipping,
                        label: 'Suppliers',
                        route: '/suppliers',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/suppliers'),
                      ),
                      _NavigationItem(
                        icon: Icons.shopping_cart_outlined,
                        selectedIcon: Icons.shopping_cart,
                        label: 'Purchases',
                        route: '/purchases',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/purchases'),
                      ),
                    ],
                  ),
                  _NavigationSection(
                    title: 'CUSTOMERS',
                    children: [
                      _NavigationItem(
                        icon: Icons.people_outline,
                        selectedIcon: Icons.people,
                        label: 'Customers',
                        route: '/customers',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/customers'),
                      ),
                      _NavigationItem(
                        icon: Icons.card_giftcard_outlined,
                        selectedIcon: Icons.card_giftcard,
                        label: 'Loyalty',
                        route: '/loyalty',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/loyalty'),
                      ),
                    ],
                  ),
                  _NavigationSection(
                    title: 'MANAGEMENT',
                    children: [
                      _NavigationItem(
                        icon: Icons.bar_chart_outlined,
                        selectedIcon: Icons.bar_chart,
                        label: 'Reports',
                        route: '/reports',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/reports'),
                      ),
                      _NavigationItem(
                        icon: Icons.admin_panel_settings_outlined,
                        selectedIcon: Icons.admin_panel_settings,
                        label: 'Staff & Permissions',
                        route: '/staff',
                        selectedRoute: selectedRoute,
                        onTap: () => _navigate(context, '/staff'),
                      ),
                      _NavigationItem(
                        icon: Icons.history_outlined,
                        selectedIcon: Icons.history,
                        label: 'Audit Log',
                        route: '/audit-log',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/audit-log'),
                      ),
                    ],
                  ),
                  _NavigationSection(
                    title: 'SYSTEM',
                    children: [
                      _NavigationItem(
                        icon: Icons.account_tree_outlined,
                        selectedIcon: Icons.account_tree,
                        label: 'Branches',
                        route: '/branches',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => _navigate(context, '/branches'),
                      ),
                      _NavigationItem(
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings,
                        label: 'Settings',
                        route: '/settings',
                        selectedRoute: selectedRoute,
                        enabled: true,
                        onTap: () => context.go('/settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationSection extends StatelessWidget {
  const _NavigationSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    required this.selectedRoute,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final String selectedRoute;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = selectedRoute == route;

    final foregroundColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    final iconColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.transparent,
        child: ListTile(
          dense: false,
          minLeadingWidth: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          selected: selected,
          selectedTileColor: theme.colorScheme.primaryContainer,
          leading: Icon(selected ? selectedIcon : icon, color: iconColor),
          title: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: foregroundColor,
            ),
          ),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}
