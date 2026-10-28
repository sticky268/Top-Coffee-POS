import '../../../../core/theme/coffee_studio_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../domain/pos_models.dart';

class ProductCard extends StatelessWidget {
  const ProductCard(
      {super.key,
      required this.product,
      required this.onTap,
      this.quantityInCart = 0});

  final PosProduct product;
  final VoidCallback onTap;
  final int quantityInCart;

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
        color: CoffeeStudioTheme.active(context)
            ? CoffeeStudioTheme.accentSurface(context, product.id)
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: quantityInCart > 0
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: quantityInCart > 0 ? 2 : 1,
          ),
        ),
        child: pos_ui.ActionSurface(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 92;
              final studio = CoffeeStudioTheme.active(context);
              final padding = studio
                  ? 8.0
                  : isCompact
                      ? 10.0
                      : 14.0;
              final nameFontSize = isCompact ? 13.0 : 15.0;
              final priceFontSize = isCompact ? 12.0 : 14.0;

              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(studio ? 8 : 12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.colorScheme.primaryContainer,
                                    theme.colorScheme.surfaceContainerLow
                                  ],
                                ),
                              ),
                              child: product.imageUrl?.isNotEmpty == true
                                  ? Image.network(product.imageUrl!,
                                      fit: BoxFit.cover,
                                      cacheWidth: (constraints.maxWidth *
                                              MediaQuery.devicePixelRatioOf(
                                                  context))
                                          .ceil()
                                          .clamp(1, 1024),
                                      errorBuilder: (_, __, ___) =>
                                          _ProductPlaceholder())
                                  : _ProductPlaceholder(),
                            ),
                            if (quantityInCart > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('$quantityInCart in cart',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              fontWeight: FontWeight.w700)),
                                ),
                              ),
                          ],
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

class _ProductPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Icon(Icons.local_cafe_rounded,
            size: 36,
            color: Theme.of(context)
                .colorScheme
                .onPrimaryContainer
                .withValues(alpha: 0.65)),
      );
}
