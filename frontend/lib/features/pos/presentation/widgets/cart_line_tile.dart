import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../application/cart_controller.dart';
import '../../domain/pos_models.dart';

class CartLineTile extends ConsumerWidget {
  const CartLineTile({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final cartNotifier = ref.read(cartControllerProvider.notifier);

    // "Latte — Medium" for a variant line, plain "Latte" otherwise — this
    // is what makes different variants of the same product visibly
    // distinct in the cart (Part 8's explicit example).
    final title = item.variant != null
        ? '${item.product.name} — ${item.variant!.name}'
        : item.product.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: title,
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.configurationLabel.isNotEmpty) Text(item.configurationLabel),
          const SizedBox(height: 4),
          Text(
            '${item.quantity} × ${currency.format(item.unitPrice)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final quantity = DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pos_ui.IconButton(
                      icon: const Icon(Icons.remove_rounded),
                      tooltip: 'Decrease quantity',
                      onPressed: () =>
                          cartNotifier.decrementQuantity(item.lineKey),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${item.quantity}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    pos_ui.IconButton(
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Increase quantity',
                      onPressed: () =>
                          cartNotifier.incrementQuantity(item.lineKey),
                    ),
                  ],
                ),
              );
              final total = Text(
                currency.format(item.lineTotal),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              );
              if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    quantity,
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: total,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  quantity,
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: total,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
