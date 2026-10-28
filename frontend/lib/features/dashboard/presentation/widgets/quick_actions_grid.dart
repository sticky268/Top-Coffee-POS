import 'package:flutter/material.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../../core/theme/coffee_studio_theme.dart';

class QuickAction {
  const QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({
    super.key,
    required this.actions,
    required this.crossAxisCount,
  });

  final List<QuickAction> actions;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: 112 + (textScale - 1).clamp(0.0, 3.0) * 50,
      children: [
        for (final action in actions) _QuickActionButton(action: action),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrimary = action.label == 'New Order';
    final iconColor = isPrimary
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final textColor =
        isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Material(
      color: isPrimary
          ? theme.colorScheme.primary
          : CoffeeStudioTheme.active(context)
              ? CoffeeStudioTheme.accentSurface(
                  context,
                  [
                    'New Order',
                    'Manage Menu',
                    'Reports',
                    'Customers',
                    'Daily Operations'
                  ].indexOf(action.label))
              : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isPrimary
            ? BorderSide.none
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: pos_ui.ActionSurface(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Tooltip(
          message: action.label,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isPrimary
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(action.icon, size: 24, color: iconColor),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    action.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
