import 'package:flutter/material.dart';
import '../theme/coffee_studio_theme.dart';

class StudioAction {
  const StudioAction(this.title, this.subtitle, this.icon, this.onTap);
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
}

/// Intrinsic-height tiles keep translated labels and enlarged text reachable.
class StudioActionBoard extends StatelessWidget {
  const StudioActionBoard(
      {super.key, required this.actions, this.featureFirst = false});
  final List<StudioAction> actions;
  final bool featureFirst;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final large = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = (box.maxWidth / (large ? 280 : 230))
            .floor()
            .clamp(1, actions.isEmpty ? 1 : actions.length.clamp(1, 3));
        final width = (box.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (var index = 0; index < actions.length; index++)
            SizedBox(
                width: width,
                child: _StudioActionTile(
                    action: actions[index],
                    index: index,
                    featured: featureFirst && index == 0)),
        ]);
      });
}

class _StudioActionTile extends StatelessWidget {
  const _StudioActionTile(
      {required this.action, required this.index, required this.featured});
  final StudioAction action;
  final int index;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink =
        featured ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final tone = switch (action.title) {
      'Combos' || 'New Order' || 'Inventory' => 0,
      'Items' || 'Manage Menu' => 1,
      'Categories' || 'Reports' => 2,
      'Modifiers' || 'Customers' || 'Orders' => 3,
      'Discounts' || 'Daily Operations' => 4,
      _ => index,
    };
    return Material(
      color: featured
          ? theme.colorScheme.primary
          : CoffeeStudioTheme.accentSurface(context, tone),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(action.icon, size: 38, color: ink),
              const SizedBox(height: 20),
              Text(action.title,
                  style: theme.textTheme.titleLarge?.copyWith(color: ink)),
              const SizedBox(height: 8),
              Text(action.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: ink)),
              const SizedBox(height: 14),
              Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.arrow_forward_rounded, color: ink)),
            ])),
      ),
    );
  }
}

class StudioFormPanel extends StatelessWidget {
  const StudioFormPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!CoffeeStudioTheme.active(context)) return child;
    return DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(20), child: child));
  }
}
