import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/coffee_studio_theme.dart';
import '../../../../core/widgets/studio_layout.dart';
import 'stat_cards_grid.dart';
import '../../../../core/theme/home_layout_preference.dart';
import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../domain/dashboard_models.dart';
import 'quick_actions_grid.dart';
import 'recent_orders_section.dart';
import 'sales_overview_chart.dart';

/// Alternate presentations of the same authorized actions and live dashboard data.
class HomeDashboardLayouts extends StatelessWidget {
  const HomeDashboardLayouts(
      {super.key,
      required this.layout,
      required this.stats,
      required this.actions,
      required this.recentOrders,
      required this.salesOverview});
  final HomeLayout layout;
  final DashboardStats stats;
  final List<QuickAction> actions;
  final List<RecentOrder> recentOrders;
  final List<SalesDataPoint> salesOverview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (CoffeeStudioTheme.active(context)) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final work = [
          ...actions.where((a) => a.label == 'New Order'),
          ...actions.where((a) => a.label != 'New Order'),
        ];
        final counter = layout == HomeLayout.coffeeCounter;
        Widget tile(QuickAction a) =>
            StudioActionBoard(featureFirst: a.label == 'New Order', actions: [
              StudioAction(
                  a.label,
                  a.label == 'New Order'
                      ? 'Start a new sale'
                      : 'Open ${a.label.toLowerCase()}',
                  a.icon,
                  a.onTap)
            ]);
        return Column(
            key: ValueKey('dashboard-${layout.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (layout == HomeLayout.modern)
                _HomeMetrics(stats: stats, modern: true)
              else
                StatCardsGrid(
                    stats: stats,
                    crossAxisCount:
                        (constraints.maxWidth / (scale > 1.4 ? 250 : 180))
                            .floor()
                            .clamp(1, 4)),
              const SizedBox(height: 24),
              if (counter && work.isNotEmpty)
                LayoutBuilder(builder: (context, box) {
                  if (box.maxWidth < 760 || scale > 1.3) {
                    return Column(children: [
                      tile(work.first),
                      const SizedBox(height: 16),
                      StudioActionBoard(actions: [
                        for (final a in work.skip(1))
                          StudioAction(a.label, 'Open ${a.label.toLowerCase()}',
                              a.icon, a.onTap)
                      ]),
                    ]);
                  }
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: tile(work.first)),
                        const SizedBox(width: 16),
                        Expanded(
                            flex: 6,
                            child: StudioActionBoard(actions: [
                              for (final a in work.skip(1))
                                StudioAction(
                                    a.label,
                                    'Open ${a.label.toLowerCase()}',
                                    a.icon,
                                    a.onTap)
                            ])),
                      ]);
                })
              else ...[
                Text('Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                StudioActionBoard(actions: [
                  for (final a in work)
                    StudioAction(a.label, 'Open ${a.label.toLowerCase()}',
                        a.icon, a.onTap)
                ]),
              ],
              const SizedBox(height: 28),
              if (constraints.maxWidth > 900 && scale <= 1.3)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _chart()),
                  const SizedBox(width: 20),
                  Expanded(child: _orders()),
                ])
              else ...[_chart(), const SizedBox(height: 20), _orders()],
            ]);
      }
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = constraints.maxWidth >= 1000 && scale <= 1.3;
      final isCounter = layout == HomeLayout.coffeeCounter;
      final metrics = _HomeMetrics(stats: stats, modern: !isCounter);
      final work = actions
          .where((action) => ['New Order', 'Daily Operations', 'Orders']
              .contains(action.label))
          .toList();
      final manage = actions.where((action) => !work.contains(action)).toList();
      const manageOrder = [
        'Manage Menu',
        'Inventory',
        'Customers',
        'Reports',
        'Receipt Settings',
        'Settings'
      ];
      manage.sort((a, b) =>
          manageOrder.indexOf(a.label).compareTo(manageOrder.indexOf(b.label)));
      Widget group(String title, List<QuickAction> values,
              {bool primary = false}) =>
          _HomePanel(
              title: title,
              child: _ActionTiles(
                  actions: values, colorful: isCounter, featureFirst: primary));
      final start = group('Start here', work, primary: true);
      final shop = group('Manage the shop', manage);
      final glance = _HomePanel(title: 'Today at a glance', child: metrics);
      return Column(
        key: ValueKey('dashboard-${layout.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCounter) ...[
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (work.isNotEmpty) Expanded(flex: 4, child: start),
                if (work.isNotEmpty) const SizedBox(width: 16),
                if (manage.isNotEmpty) Expanded(flex: 4, child: shop),
                if (manage.isNotEmpty) const SizedBox(width: 16),
                Expanded(flex: 3, child: glance),
              ])
            else ...[
              if (work.isNotEmpty) start,
              if (work.isNotEmpty) const SizedBox(height: 16),
              if (manage.isNotEmpty) shop,
              if (manage.isNotEmpty) const SizedBox(height: 16),
              glance,
            ],
          ] else ...[
            metrics,
            const SizedBox(height: 20),
            _HomePanel(
                title: 'Quick Actions',
                child: _ActionTiles(actions: [
                  ...actions.where((action) => action.label == 'New Order'),
                  ...actions.where((action) => action.label != 'New Order'),
                ], colorful: false)),
          ],
          const SizedBox(height: 20),
          if (constraints.maxWidth >= 850 && scale <= 1.3)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _chart()),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _orders()),
            ])
          else ...[
            _chart(),
            const SizedBox(height: 16),
            _orders(),
          ],
        ],
      );
    });
  }

  Widget _chart() => _HomePanel(
      title: 'Sales Overview — Last 7 Days',
      child: SalesOverviewChart(
          data: salesOverview,
          height: 190,
          barColor: AppColors.ready,
          latestBarColor: AppColors.caramel));
  Widget _orders() => _HomePanel(
      title: 'Recent Orders', child: RecentOrdersSection(orders: recentOrders));
}

class HomeTaskPanel extends StatelessWidget {
  const HomeTaskPanel(
      {super.key,
      required this.title,
      required this.actions,
      required this.colorful,
      this.featureFirst = false});
  final String title;
  final List<QuickAction> actions;
  final bool colorful, featureFirst;
  @override
  Widget build(BuildContext context) => _HomePanel(
      title: title,
      child: _ActionTiles(
          actions: actions, colorful: colorful, featureFirst: featureFirst));
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );
}

class _HomeMetrics extends StatelessWidget {
  const _HomeMetrics({required this.stats, required this.modern});
  final DashboardStats stats;
  final bool modern;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '\$');
    final tiles = [
      _Metric(
          label: "Today's Sales",
          value: money.format(stats.todaysSales),
          icon: Icons.bar_chart_rounded,
          color: AppColors.ready,
          hero: modern,
          compact: !modern),
      _Metric(
          label: "Today's Orders",
          value: '${stats.todaysOrders}',
          icon: Icons.shopping_bag_outlined,
          color: AppColors.info,
          compact: !modern),
      _Metric(
          label: 'Average Order',
          value: money.format(stats.averageOrderValue),
          icon: Icons.credit_card_outlined,
          color: AppColors.plum,
          compact: !modern),
      _Metric(
          label: 'Low Stock',
          value: '${stats.lowStockItemCount} items',
          icon: Icons.inventory_2_outlined,
          color:
              stats.lowStockItemCount > 0 ? AppColors.error : AppColors.ready,
          compact: !modern),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (modern && constraints.maxWidth >= 800 && scale <= 1.3) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: tiles.first),
          for (final tile in tiles.skip(1)) ...[
            const SizedBox(width: 12),
            Expanded(child: tile),
          ],
        ]);
      }
      final columns = (constraints.maxWidth /
              (scale > 1.4
                  ? 250
                  : modern
                      ? 165
                      : 140))
          .floor()
          .clamp(1, 2);
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tiles.first,
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final tile in tiles.skip(1))
            SizedBox(
                width: !modern && tile == tiles.last
                    ? constraints.maxWidth
                    : width,
                child: tile),
        ]),
      ]);
    });
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.hero = false,
      this.compact = false});
  final String label, value;
  final IconData icon;
  final Color color;
  final bool hero, compact;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        hero ? AppColors.white : AppColors.semantic(context, color);
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: hero ? const Color(0xFF145A52) : AppColors.tint(context, color),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: foreground, size: 26),
        SizedBox(height: compact ? 8 : 14),
        Text(value,
            style: theme.textTheme.headlineMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: hero ? 40 : 26)),
        const SizedBox(height: 6),
        Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: hero ? AppColors.white : theme.colorScheme.onSurface)),
      ]),
    );
  }
}

class _ActionTiles extends StatelessWidget {
  const _ActionTiles(
      {required this.actions,
      required this.colorful,
      this.featureFirst = false});
  final List<QuickAction> actions;
  final bool colorful;
  final bool featureFirst;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (scale > 1.4 ? 240 : 165))
            .floor()
            .clamp(1, colorful ? 2 : 4);
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        // New Order is always the largest shortcut in Coffee Counter.
        final featured = featureFirst
            ? actions
                .where((action) => action.label.startsWith('New '))
                .firstOrNull
            : null;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (featured != null) ...[
                _HomeAction(
                    action: featured, colorful: colorful, featured: true),
                const SizedBox(height: 12),
              ],
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final action
                    in actions.where((action) => action != featured))
                  SizedBox(
                      width: width,
                      child: _HomeAction(action: action, colorful: colorful)),
              ]),
            ]);
      });
}

class _HomeAction extends StatelessWidget {
  const _HomeAction(
      {required this.action, required this.colorful, this.featured = false});
  final QuickAction action;
  final bool colorful, featured;
  Color get color => switch (action.label) {
        'New Order' || 'Inventory' => const Color(0xFF168372),
        'Daily Operations' => const Color(0xFFA96700),
        'Orders' || 'Customers' => const Color(0xFF146CB5),
        'Manage Menu' => const Color(0xFFC4594C),
        'Receipt Settings' => const Color(0xFFAD4C69),
        'Reports' => const Color(0xFF7555A6),
        _ => AppColors.info,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = action.label.startsWith('New ');
    final foreground = primary
        ? AppColors.white
        : theme.brightness == Brightness.dark
            ? Color.lerp(color, AppColors.white, .45)!
            : color;
    final background = primary
        ? const Color(0xFF145A52)
        : colorful
            ? Color.alphaBlend(
                foreground.withValues(alpha: 0.17), theme.colorScheme.surface)
            : theme.colorScheme.surfaceContainerLow;
    return Semantics(
        button: true,
        child: Material(
          color: background,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: pos_ui.ActionSurface(
            key: ValueKey('home-action-${action.label}'),
            borderRadius: BorderRadius.circular(18),
            onTap: action.onTap,
            child: Padding(
              padding: EdgeInsets.all(featured ? 22 : 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(action.icon,
                          size: featured ? 48 : 28, color: foreground),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded,
                          size: 20, color: foreground),
                    ]),
                    SizedBox(height: featured ? 28 : 16),
                    Text(action.label,
                        style: (featured
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.titleSmall)
                            ?.copyWith(
                                color: primary
                                    ? AppColors.white
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700)),
                    if (featured) ...[
                      const SizedBox(height: 8),
                      const Text('Start a new sale',
                          style: TextStyle(color: AppColors.white)),
                    ],
                  ]),
            ),
          ),
        ));
  }
}
