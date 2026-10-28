import 'package:flutter/material.dart';
import '../theme/coffee_studio_theme.dart';

/// Keeps long lists and forms readable on a tablet without adding a second
/// scroll view or changing their refresh, pagination or keyboard behavior.
class PageContent extends StatelessWidget {
  const PageContent(
      {super.key,
      required this.child,
      this.maxWidth = 1000,
      this.form = false});
  final Widget child;
  final double maxWidth;
  final bool form;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(
              width: double.infinity,
              child: form && CoffeeStudioTheme.active(context)
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              borderRadius: BorderRadius.circular(16)),
                          child: child))
                  : child),
        ),
      );
}

/// Values wrap below their labels when space or the user's text size requires
/// it. Neither business names nor contact information are truncated.
class DetailValue extends StatelessWidget {
  const DetailValue({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
          final valueWidget = Text(value, style: theme.textTheme.bodyLarge);
          if (constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: valueWidget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A list record with a full-width detail area instead of a cramped trailing
/// column. Its one tap action and optional menu stay independent.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.details,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? details;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (CoffeeStudioTheme.active(context) &&
        MediaQuery.sizeOf(context).width >= 900 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(children: [
              if (leading != null) ...[
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: CoffeeStudioTheme.accentSurface(
                            context, title.length),
                        borderRadius: BorderRadius.circular(12)),
                    child: leading),
                const SizedBox(width: 18),
              ],
              Expanded(
                  flex: 3,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (subtitle != null) ...[
                          const SizedBox(height: 5),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ])),
              if (details != null) ...[
                const SizedBox(width: 24),
                Expanded(flex: 2, child: details!),
              ],
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ])),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            if (details != null) ...[const SizedBox(height: 12), details!],
          ],
        ),
      ),
    );
  }
}
