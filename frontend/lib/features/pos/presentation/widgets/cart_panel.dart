import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../application/cart_controller.dart';
import '../../domain/pos_models.dart';
import 'cart_line_tile.dart';

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, this.selectedTable});

  final PosTable? selectedTable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final cartNotifier = ref.read(cartControllerProvider.notifier);
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Order Summary',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selectedTable != null) ...[
                      const SizedBox(width: 8),
                      Chip(
                        avatar: const Icon(Icons.table_restaurant, size: 16),
                        label: Text(selectedTable!.name),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),
              if (!cart.isEmpty)
                pos_ui.DangerButton.outlinedIcon(
                  onPressed: () => _confirmClearCart(context, cartNotifier),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear Cart'),
                ),
            ],
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? const _EmptyCart()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      CartLineTile(item: cart.items[index]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryLine(
                label: 'Subtotal',
                value: currency.format(cart.subtotal),
              ),
              _DiscountRow(
                discountTotal: cart.discountTotal,
                onChanged: cartNotifier.setDiscount,
                currency: currency,
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  Text(
                    currency.format(cart.total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              pos_ui.PosActionButton(
                onPressed: cart.isEmpty
                    ? null
                    : () => context.push('/pos/checkout', extra: selectedTable),
                child: const Text('Review Order'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearCart(
    BuildContext context,
    CartController notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This removes every item currently in the cart.'),
        actions: [
          pos_ui.SecondaryButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          pos_ui.DangerButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      notifier.clear();
    }
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A simple manual flat-amount discount input Ã¢â‚¬â€ deliberately no
/// percentage tiers or coupon rules, per the task's explicit "prepare the
/// UI/state for it, but don't add complicated discount rules yet".
class _DiscountRow extends StatefulWidget {
  const _DiscountRow({
    required this.discountTotal,
    required this.onChanged,
    required this.currency,
  });

  final double discountTotal;
  final ValueChanged<double> onChanged;
  final NumberFormat currency;

  @override
  State<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends State<_DiscountRow> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController(
    text: widget.discountTotal > 0
        ? widget.discountTotal.toStringAsFixed(2)
        : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discount', style: theme.textTheme.bodyMedium),
                  if (widget.discountTotal > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '- ${widget.currency.format(widget.discountTotal)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            pos_ui.OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.discount_outlined, size: 18),
              label: Text(
                widget.discountTotal > 0 ? 'Edit discount' : 'Add discount',
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('Discount', style: theme.textTheme.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: '\$ ',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _apply(),
            ),
          ),
          pos_ui.IconButton(
            icon: const Icon(Icons.check, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }

  void _apply() {
    final value = double.tryParse(_controller.text) ?? 0;
    widget.onChanged(value);
    setState(() => _editing = false);
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 36,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Your cart is empty',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
