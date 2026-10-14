import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
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

    return Tooltip(
      message: '${product.name} · $priceLabel',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: pos_ui.ActionSurface(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: theme.colorScheme.surfaceContainerLow,
                          child:
                              product.imageUrl != null &&
                                  product.imageUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    product.imageUrl!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(
                                        Icons.local_cafe_outlined,
                                        size: 32,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    Icons.local_cafe_outlined,
                                    size: 32,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: nameFontSize,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: priceFontSize,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          product.hasVariants
                              ? Icons.tune_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
