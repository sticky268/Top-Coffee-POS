import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../pos/domain/pos_models.dart';

/// A browsing/management list row — distinct from POS's ProductCard,
/// which is a compact tap-to-add-to-cart grid tile. This screen is for
/// viewing and managing the catalog, not building an order, so a denser
/// informational list row (category, variant count) fits better than a
/// large touch target, and now also carries Edit/Disable actions.
class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.product,
    required this.onEdit,
    required this.canModify,
    required this.onDisable,
    this.isDisabling = false,
  });

  final PosProduct product;

  /// Whether subscription write access is currently available.
  final bool canModify;

  /// The whole row is tappable for Edit — the most common action.
  final VoidCallback onEdit;

  /// Reached via the trailing menu, behind its own confirmation dialog —
  /// deliberately not a one-tap action, since it changes catalog
  /// visibility.
  final VoidCallback onDisable;

  /// True while a disable request for this specific product is in
  /// flight — swaps the trailing content for a spinner and disables the
  /// menu, preventing a second tap from firing a duplicate request.
  final bool isDisabling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    final priceLabel = product.hasVariants
        ? 'From ${currency.format(product.variants.map((v) => v.price).reduce((a, b) => a < b ? a : b))}'
        : currency.format(product.price);

    final subtitleParts = <String>[
      if (product.category != null) product.category!.name,
      if (product.hasVariants)
        '${product.variants.length} option${product.variants.length == 1 ? '' : 's'}',
    ];

    return ListTile(
      onTap: !canModify || isDisabling ? null : onEdit,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: product.imageUrl != null && product.imageUrl!.isNotEmpty
            ? ClipOval(
                child: Image.network(
                  product.imageUrl!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.local_cafe_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            : Icon(
                Icons.local_cafe_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
      ),
      title: Text(product.name),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: isDisabling
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(priceLabel, style: theme.textTheme.titleMedium),
                PopupMenuButton<String>(
                  enabled: canModify && !isDisabling,
                  tooltip: canModify
                      ? 'More actions'
                      : 'Subscription is read-only',
                  onSelected: (value) {
                    if (value == 'disable' && canModify) {
                      onDisable();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'disable', child: Text('Disable')),
                  ],
                ),
              ],
            ),
    );
  }
}
