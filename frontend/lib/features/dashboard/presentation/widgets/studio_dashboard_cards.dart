import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../domain/dashboard_models.dart';
import 'quick_actions_grid.dart';

/// Bundled artwork stays available offline; all labels and values remain live.
class StudioWelcomeBanner extends StatelessWidget {
  const StudioWelcomeBanner({super.key, required this.greeting});
  final String greeting;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 600;
          final banner = Stack(children: [
            if (!narrow)
              Positioned.fill(
                  child: Image.asset('assets/dashboard/coffee_welcome.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      excludeFromSemantics: true)),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
              const Color(0xFFFFF8E9),
              const Color(0xFFFFF8E9).withValues(alpha: narrow ? 1 : .05)
            ])))),
            Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: 110,
                        maxWidth: box.maxWidth > 700
                            ? box.maxWidth * .64
                            : box.maxWidth),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wb_sunny_outlined,
                              color: Color(0xFFAE772A), size: 28),
                          const SizedBox(height: 10),
                          Text(greeting,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      color: const Color(0xFF342D24),
                                      fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          const Text('Your coffee counter, at a glance.',
                              style: TextStyle(color: Color(0xFF655A48))),
                        ]))),
          ]);
          if (!narrow) return banner;
          return ColoredBox(
              color: const Color(0xFFFFF8E9),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        height: 110,
                        child: Image.asset(
                            'assets/dashboard/coffee_welcome.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            excludeFromSemantics: true)),
                    banner,
                  ]));
        }),
      );
}

class StudioDashboardMetrics extends StatelessWidget {
  const StudioDashboardMetrics({super.key, required this.stats});
  final DashboardStats stats;
  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '\$');
    final values = [
      (
        "Today's Sales",
        money.format(stats.todaysSales),
        Icons.payments_outlined,
        const Color(0xFF247B68)
      ),
      (
        "Today's Orders",
        '${stats.todaysOrders}',
        Icons.shopping_bag_outlined,
        const Color(0xFFAF7C24)
      ),
      (
        'Average Order',
        money.format(stats.averageOrderValue),
        Icons.credit_card,
        const Color(0xFF3C79A4)
      ),
      (
        'Low Stock',
        '${stats.lowStockItemCount} items',
        Icons.inventory_2_outlined,
        const Color(0xFFB85843)
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final large = MediaQuery.textScalerOf(context).scale(14) > 20;
      final availableColumns =
          (box.maxWidth / (large ? 320 : 220)).floor().clamp(1, 4);
      final columns = availableColumns == 3 ? 2 : availableColumns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final v in values)
          SizedBox(
              width: (box.maxWidth - 12 * (columns - 1)) / columns,
              child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Color.alphaBlend(v.$4.withValues(alpha: .13),
                          Theme.of(context).colorScheme.surface),
                      border: Border.all(color: v.$4.withValues(alpha: .18)),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    _Badge(icon: v.$3, color: v.$4),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(v.$1,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 6),
                          Text(v.$2,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ])),
                  ]))),
      ]);
    });
  }
}

class StudioDashboardActions extends StatelessWidget {
  const StudioDashboardActions({super.key, required this.actions});
  final List<QuickAction> actions;
  @override
  Widget build(BuildContext context) {
    final featured = actions.where((a) => a.label == 'New Order').firstOrNull;
    final main = [
      for (final name in [
        'Manage Menu',
        'Reports',
        'Customers',
        'Daily Operations'
      ])
        ...actions.where((a) => a.label == name)
    ];
    final rest =
        actions.where((a) => a != featured && !main.contains(a)).toList();
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 800 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      Widget grid(List<QuickAction> items, int maxColumns,
              {bool compact = false}) =>
          LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth /
                    (MediaQuery.textScalerOf(context).scale(14) > 20
                        ? 300
                        : 220))
                .floor()
                .clamp(1, maxColumns);
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final action in items)
                SizedBox(
                    width:
                        (constraints.maxWidth - 12 * (columns - 1)) / columns,
                    child: _ActionCard(action: action, compact: compact))
            ]);
          });
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (wide && featured != null && main.isNotEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                flex: 4, child: _ActionCard(action: featured, featured: true)),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: grid(main, 2)),
          ])
        else ...[
          if (featured != null) _ActionCard(action: featured, featured: true),
          if (featured != null && main.isNotEmpty) const SizedBox(height: 12),
          if (main.isNotEmpty) grid(main, 2),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 16),
          grid(rest, 4, compact: true)
        ],
      ]);
    });
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(
      {required this.action, this.featured = false, this.compact = false});
  final QuickAction action;
  final bool featured, compact;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (action.label) {
      'Manage Menu' => const Color(0xFFC8793C),
      'Reports' => const Color(0xFF8563AC),
      'Customers' => const Color(0xFF4385AD),
      'Daily Operations' => const Color(0xFFAB802F),
      _ => const Color(0xFF237F6B),
    };
    final subtitle = switch (action.label) {
      'Manage Menu' => 'Items, combos & modifiers',
      'Reports' => 'Sales and performance',
      'Customers' => 'Customer records',
      'Daily Operations' => 'Shifts and cash',
      _ => 'Start a new sale',
    };
    return Material(
        color: featured
            ? const Color(0xFF146653)
            : compact
                ? theme.colorScheme.surface
                : Color.alphaBlend(
                    color.withValues(alpha: .15), theme.colorScheme.surface),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withValues(alpha: .2))),
        clipBehavior: Clip.antiAlias,
        child: pos_ui.ActionSurface(
            key: ValueKey('home-action-${action.label}'),
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Stack(children: [
              if (featured)
                const Positioned.fill(
                    child: ExcludeSemantics(
                        child: CustomPaint(painter: _CoffeeLeaves()))),
              Padding(
                  padding: EdgeInsets.all(featured ? 24 : 16),
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: featured
                              ? 176
                              : compact
                                  ? 28
                                  : 74),
                      child: featured
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  const _Badge(
                                      icon: Icons.add_shopping_cart,
                                      color: Colors.white),
                                  const SizedBox(height: 26),
                                  Text(action.label,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  const Text('Start a new sale',
                                      style: TextStyle(color: Colors.white)),
                                  const SizedBox(height: 14),
                                  const CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.white,
                                      child: Icon(Icons.arrow_forward,
                                          color: Color(0xFF146653), size: 20)),
                                ])
                          : Row(children: [
                              if (compact)
                                Icon(action.icon,
                                    size: 22, color: theme.colorScheme.primary)
                              else
                                _Badge(icon: action.icon, color: color),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(action.label,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700)),
                                    if (!compact) ...[
                                      const SizedBox(height: 5),
                                      Text(subtitle,
                                          style: theme.textTheme.bodySmall)
                                    ],
                                  ])),
                            ]))),
            ])));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .13), shape: BoxShape.circle),
      child: Icon(icon,
          color: Theme.of(context).brightness == Brightness.dark
              ? Color.lerp(color, Colors.white, .45)
              : color,
          size: 24));
}

/// Decorative coffee sprig, drawn independently of labels and touch targets.
class _CoffeeLeaves extends CustomPainter {
  const _CoffeeLeaves();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDAC085).withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.save();
    canvas.translate(size.width * .76, size.height * .95);
    canvas.rotate(.28);
    canvas.drawPath(
        Path()
          ..moveTo(0, 10)
          ..quadraticBezierTo(-25, -90, 15, -220),
        paint);
    for (var i = 0; i < 6; i++) {
      final y = -i * 30.0 - 12;
      for (final side in [-1.0, 1.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(0, y)
              ..quadraticBezierTo(58 * side, y - 5, 44 * side, y - 40)
              ..quadraticBezierTo(10 * side, y - 42, 0, y)
              ..close(),
            paint);
        canvas.drawLine(Offset(0, y), Offset(40 * side, y - 35), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoffeeLeaves oldDelegate) => false;
}
