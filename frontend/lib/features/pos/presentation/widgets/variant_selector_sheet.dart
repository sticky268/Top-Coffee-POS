import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/cart_controller.dart';
import '../../domain/pos_models.dart';

/// Shown when a product with variants is tapped (Part 7: "Tap product â†’
/// show variant selection"). Selecting a variant adds it to the cart and
/// closes the sheet.
Future<void> showVariantSelector(
  BuildContext context,
  WidgetRef ref,
  PosProduct product, {
  void Function(PosProduct product, PosProductVariant variant)?
  onVariantSelected,
}) {
  final currency = NumberFormat.currency(symbol: '\$');

  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(product.name, style: theme.textTheme.titleLarge),
            ),
            for (final variant in product.variants)
              ListTile(
                title: Text(variant.name),
                trailing: Text(
                  currency.format(variant.price),
                  style: theme.textTheme.titleMedium,
                ),
                onTap: () {
                  if (onVariantSelected != null) {
                    onVariantSelected(product, variant);
                  } else {
                    ref
                        .read(cartControllerProvider.notifier)
                        .addItem(product, variant: variant);
                  }
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
