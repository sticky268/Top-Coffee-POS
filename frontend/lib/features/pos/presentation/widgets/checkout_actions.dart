import 'package:flutter/material.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;

/// Payment summary and actions fit the review page as one bordered panel.
/// Checkout pages use inline mode so this panel scrolls with the order.
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
            Text('Total due',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(totalLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            if (secondaryTotalLabel != null)
              Text(secondaryTotalLabel!, style: theme.textTheme.bodySmall),
          ],
        );
        final buttonStyle = wide
            ? const ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.fromHeight(56)))
            : null;
        final print = pos_ui.PrimaryButton.icon(
          style: buttonStyle,
          onPressed: enabled && !isSubmitting ? () => onComplete(true) : null,
          isLoading: isSubmitting,
          icon: const Icon(Icons.receipt_long_outlined, size: 20),
          label: const Text('Complete & Print'),
        );
        final complete = pos_ui.OutlinedButton.icon(
          style: buttonStyle,
          onPressed: enabled && !isSubmitting ? () => onComplete(false) : null,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
          label: const Text('Complete Sale'),
        );
        final save = onSave == null
            ? null
            : pos_ui.SecondaryButton.icon(
                onPressed: isSubmitting ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Order'),
              );
        final content = Material(
          color: theme.colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                total,
                const SizedBox(height: 16),
                if (save != null) ...[
                  save,
                  const SizedBox(height: 10),
                ],
                print,
                const SizedBox(height: 10),
                complete,
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
