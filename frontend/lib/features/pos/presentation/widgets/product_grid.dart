import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/cart_controller.dart';
import '../../application/pos_catalog_controller.dart';
import '../../application/pos_catalog_state.dart';
import '../../domain/pos_models.dart';
import 'product_card.dart';
import 'variant_selector_sheet.dart';
import 'menu_selection_sheet.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.crossAxisCount,
    this.sliver = false,
    this.onProductSelected,
    this.onVariantSelected,
    this.onConfiguredSelected,
  });

  final void Function(CartItem item)? onConfiguredSelected;
  final List<PosProduct> products;
  final int crossAxisCount;
  final bool sliver;
  final void Function(PosProduct product)? onProductSelected;
  final void Function(PosProduct product, PosProductVariant variant)?
      onVariantSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (products.isEmpty) {
      return sliver
          ? const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyProducts(),
            )
          : const _EmptyProducts();
    }

    final quantities = <int, int>{};
    for (final item in ref.watch(
      cartControllerProvider.select((cart) => cart.items),
    )) {
      quantities.update(
        item.product.id,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    Widget buildGrid(double width) {
      final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
      // Use the catalog pane's width; the tablet cart takes its own space.
      final columns = ((width - 16) / (scale > 1.4 ? 256 : 166)).floor().clamp(
            1,
            crossAxisCount,
          );
      final tileWidth = (width - 32 - 16 * (columns - 1)) / columns;
      // Large type needs room for names rather than a taller photo.
      final tileHeight = scale > 1.4
          ? 132 + scale * 68
          : (tileWidth / 1.05).clamp(180.0, 280.0);
      final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: tileHeight,
      );
      final children = SliverChildBuilderDelegate((context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          quantityInCart: quantities[product.id] ?? 0,
          onTap: () async {
            if (product.needsConfiguration) {
              final catalog = ref.read(posCatalogControllerProvider);
              final item = await showMenuSelection(
                context,
                product,
                catalog:
                    catalog is PosCatalogLoaded ? catalog.products : products,
              );
              if (item == null || !context.mounted) return;
              if (onConfiguredSelected != null) {
                onConfiguredSelected!(item);
              } else {
                ref.read(cartControllerProvider.notifier).addItem(
                      product,
                      variant: item.variant,
                      modifierIds: item.modifierIds,
                      comboSelections: item.comboSelections,
                      extraCents: item.extraCents,
                      configurationLabel: item.configurationLabel,
                    );
              }
            } else if (product.hasVariants) {
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
      }, childCount: products.length);
      if (sliver) {
        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(gridDelegate: gridDelegate, delegate: children),
        );
      }
      return GridView.custom(
        padding: const EdgeInsets.all(16),
        gridDelegate: gridDelegate,
        childrenDelegate: children,
      );
    }

    return sliver
        ? SliverLayoutBuilder(
            builder: (context, constraints) =>
                buildGrid(constraints.crossAxisExtent),
          )
        : LayoutBuilder(
            builder: (context, constraints) => buildGrid(constraints.maxWidth),
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
            Icon(
              Icons.coffee_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No products available', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
