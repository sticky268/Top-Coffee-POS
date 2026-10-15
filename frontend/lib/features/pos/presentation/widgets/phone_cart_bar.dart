import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../application/cart_controller.dart';
import '../../domain/pos_models.dart';
import 'cart_panel.dart';

class PhoneCartBar extends ConsumerWidget {
  const PhoneCartBar({super.key, this.selectedTable});

  final PosTable? selectedTable;

  Future<void> _openCart(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: pos_ui.IconButton(
              tooltip: 'Close cart',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          Expanded(child: CartPanel(selectedTable: selectedTable)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final count = cart.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final total = NumberFormat.currency(symbol: '\$').format(cart.total);
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            pos_ui.OutlinedButton.icon(
              onPressed: cart.isEmpty ? null : () => _openCart(context),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: Text('View cart · $count ${count == 1 ? 'item' : 'items'} · $total'),
            ),
            const SizedBox(height: 8),
            pos_ui.PosActionButton(
              onPressed: cart.isEmpty
                  ? null
                  : () => context.push('/pos/checkout', extra: selectedTable),
              child: const Text('Review Order'),
            ),
          ],
        ),
      ),
    );
  }
}
