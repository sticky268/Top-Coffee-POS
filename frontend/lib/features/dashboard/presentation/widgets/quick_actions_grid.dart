import 'package:flutter/material.dart';

class QuickAction {
  const QuickAction({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, required this.actions, required this.crossAxisCount});

  final List<QuickAction> actions;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      // 1.25 rather than 1.4 — a little more height headroom before the
      // compact tier below has to kick in (same rationale as StatCardsGrid).
      childAspectRatio: 1.25,
      children: [for (final action in actions) _QuickActionButton(action: action)],
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
    final iconColor = isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant;
    final textColor = isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Material(
      color: isPrimary ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: action.onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Genuine responsive tiering: below this height, shrink
            // padding/spacing/font so the button looks intentional at
            // small sizes, not just "doesn't overflow".
            final isCompact = constraints.maxHeight < 64;
            final padding = isCompact ? 6.0 : 12.0;
            final gap = isCompact ? 2.0 : 8.0;
            final labelFontSize = isCompact ? 11.0 : null; // null keeps theme default

            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Expanded + FittedBox is what actually prevents
                  // overflow: the icon shrinks to whatever space is left
                  // after the fixed-height label line, instead of always
                  // rendering at a fixed 28px regardless of available room.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Icon(action.icon, size: 28, color: iconColor),
                    ),
                  ),
                  SizedBox(height: gap),
                  Text(
                    action.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: textColor,
                      fontSize: labelFontSize,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
