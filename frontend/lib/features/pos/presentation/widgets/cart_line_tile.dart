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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${currency.format(item.unitPrice)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          pos_ui.IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            visualDensity: VisualDensity.compact,
            tooltip: 'Decrease quantity',
            onPressed: () => cartNotifier.decrementQuantity(item.lineKey),
          ),
          Text('${item.quantity}', style: theme.textTheme.titleMedium),
          pos_ui.IconButton(
            icon: const Icon(Icons.add_circle_outline),
            visualDensity: VisualDensity.compact,
            tooltip: 'Increase quantity',
            onPressed: () => cartNotifier.incrementQuantity(item.lineKey),
          ),
          SizedBox(
            width: 60,
            child: Text(
              currency.format(item.lineTotal),
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
