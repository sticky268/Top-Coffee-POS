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
    required this.enabled,
    required this.isSubmitting,
    required this.onComplete,
  });

  final String totalLabel;
  final String? secondaryTotalLabel;
  final double? maxHeight;
  final bool enabled;
  final bool isSubmitting;
  final ValueChanged<bool> onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight ?? height * 0.48),
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('Total due', style: theme.textTheme.titleMedium),
                      Text(totalLabel, style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ],
                  ),
                  if (secondaryTotalLabel != null)
                    Text(secondaryTotalLabel!, textAlign: TextAlign.end),
                  const SizedBox(height: 8),
                  pos_ui.PosActionButton.icon(
                    onPressed: enabled && !isSubmitting
                        ? () => onComplete(true) : null,
                    isLoading: isSubmitting,
                    icon: const Icon(Icons.receipt_long_outlined, size: 20),
                    label: const Text('Complete & Print'),
                  ),
                  const SizedBox(height: 8),
                  pos_ui.OutlinedButton.icon(
                    onPressed: enabled && !isSubmitting
                        ? () => onComplete(false) : null,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                    label: const Text('Complete Sale'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
