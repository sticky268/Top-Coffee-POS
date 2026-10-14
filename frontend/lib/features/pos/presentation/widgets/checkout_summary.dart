import 'package:flutter/material.dart';

/// Presentation only: callers provide the already calculated currency value.
class CheckoutAmountRow extends StatelessWidget {
  const CheckoutAmountRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });
  final String label, value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final valueText = Text(
      value,
      style:
          (emphasized
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.bodyLarge)
              ?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              MediaQuery.textScalerOf(context).scale(14) > 20 ||
              constraints.maxWidth < 240;
          if (stacked)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), valueText],
            );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: labelText),
              const SizedBox(width: 12),
              Flexible(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class CheckoutTotalCard extends StatelessWidget {
  const CheckoutTotalCard({
    super.key,
    this.label = 'Total',
    required this.value,
  });
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: CheckoutAmountRow(
        label: label,
        value: value,
        emphasized: true,
        valueColor: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class CheckoutChoice {
  const CheckoutChoice(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;
}

class CheckoutChoiceSelector extends StatelessWidget {
  const CheckoutChoiceSelector({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final List<CheckoutChoice> choices;
  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = largeText
            ? 1
            : constraints.maxWidth >= 600
            ? choices.length
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              SizedBox(
                width: width,
                child: Semantics(
                  selected: selected == choice.value,
                  child: OutlinedButton.icon(
                    onPressed: enabled ? () => onChanged(choice.value) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      backgroundColor: selected == choice.value
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surface,
                      foregroundColor: selected == choice.value
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                      side: BorderSide(
                        color: selected == choice.value
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    icon: Icon(choice.icon, size: 20),
                    label: Text(choice.label, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class CheckoutOrderLine extends StatelessWidget {
  const CheckoutOrderLine({
    super.key,
    required this.title,
    this.variant,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
  final String title, unitPrice, lineTotal;
  final String? variant;
  final int quantity;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (variant != null)
            Text(
              variant!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          CheckoutAmountRow(label: '$quantity × $unitPrice', value: lineTotal),
        ],
      ),
    );
  }
}
