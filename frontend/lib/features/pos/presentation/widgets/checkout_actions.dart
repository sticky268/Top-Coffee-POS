import 'package:flutter/material.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;

/// Payment controls remain outside the scrollable order review.
/// On short windows the footer itself can scroll without overflowing the page.
class CheckoutActions extends StatelessWidget {
  const CheckoutActions({
    super.key,
    required this.totalLabel,
    this.secondaryTotalLabel,
    this.maxHeight,
    this.inline = false,
    required this.enabled,
    required this.isSubmitting,
    required this.onComplete,
    this.onSave,
  });

  final String totalLabel;
  final String? secondaryTotalLabel;
  final double? maxHeight;
  final bool inline;
  final bool enabled;
  final bool isSubmitting;
  final ValueChanged<bool> onComplete;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom;
        final wide = constraints.maxWidth >= 700 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        final total = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total due', style: theme.textTheme.labelLarge),
            Text(totalLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            if (secondaryTotalLabel != null)
              Text(secondaryTotalLabel!, style: theme.textTheme.bodySmall),
          ],
        );
        final print = pos_ui.PosActionButton.icon(
          onPressed: enabled && !isSubmitting ? () => onComplete(true) : null,
          isLoading: isSubmitting,
          icon: const Icon(Icons.receipt_long_outlined, size: 20),
          label: const Text('Complete & Print'),
        );
        final complete = pos_ui.OutlinedButton.icon(
          onPressed: enabled && !isSubmitting ? () => onComplete(false) : null,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
          label: const Text('Complete Sale'),
        );
        final save = onSave == null
            ? null
            : pos_ui.SecondaryButton.icon(
                onPressed: isSubmitting ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Order · Pay Later'),
              );
        final content = Material(
          color: theme.colorScheme.surface,
          elevation: 0,
          shape:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wide)
                  Row(children: [
                    Expanded(flex: 2, child: total),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: print),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: complete),
                  ])
                else ...[
                  Row(children: [
                    Expanded(child: total),
                  ]),
                  const SizedBox(height: 8),
                  print,
                  const SizedBox(height: 8),
                  complete,
                ],
                if (save != null) ...[
                  const SizedBox(height: 8),
                  save,
                ],
              ],
            ),
          ),
        );
        if (inline) return content;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight ?? height * 0.48),
          child: SingleChildScrollView(child: content),
        );
      },
    );
  }
}
