import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/cart_controller.dart';
import '../../domain/pos_models.dart';
import 'product_card.dart';
import 'variant_selector_sheet.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.crossAxisCount,
    this.onProductSelected,
    this.onVariantSelected,
  });

  final List<PosProduct> products;
  final int crossAxisCount;
  final void Function(PosProduct product)? onProductSelected;
  final void Function(PosProduct product, PosProductVariant variant)? onVariantSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (products.isEmpty) {
      return const _EmptyProducts();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          onTap: () {
            if (product.hasVariants) {
              showVariantSelector(
                context,
                ref,
                product,
                onVariantSelected: onVariantSelected,
              );
            } else if (onProductSelected != null) {
              onProductSelected!(product);
            } else {
              ref.read(cartControllerProvider.notifier).addItem(product);
            }
          },
        );
      },
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coffee_outlined, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No products available', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

