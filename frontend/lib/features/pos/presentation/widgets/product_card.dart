import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/pos_models.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});

  final PosProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    // A product with variants doesn't have one fixed price — show "From
    // $X" using the cheapest variant, rather than the potentially
    // misleading base `product.price` alone.
    final priceLabel = product.hasVariants
        ? 'From ${currency.format(product.variants.map((v) => v.price).reduce((a, b) => a < b ? a : b))}'
        : currency.format(product.price);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Same responsive-tiering + Expanded pattern established in
            // StatCardsGrid to guarantee no RenderFlex overflow at small
            // cell sizes, not just avoid it at "normal" sizes.
            final isCompact = constraints.maxHeight < 92;
            final padding = isCompact ? 10.0 : 14.0;
            final nameFontSize = isCompact ? 13.0 : 15.0;
            final priceFontSize = isCompact ? 12.0 : 14.0;

            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: nameFontSize),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: priceFontSize,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
