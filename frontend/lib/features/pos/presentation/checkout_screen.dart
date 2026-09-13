import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../application/cart_controller.dart';
import '../application/cart_state.dart';
import '../application/checkout_controller.dart';
import '../application/checkout_state.dart';
import '../domain/pos_models.dart';

/// Order review + payment screen, reached via the cart's "Review Order" /
/// "Checkout" action. Reads the cart at build time; on a successful order,
/// clears the cart via the existing CartController (no new cart-clearing
/// logic here) and shows a confirmation.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    this.initialTable,
  });

  final PosTable? initialTable;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _paymentMethod = 'cash';
PosTable? _selectedTable;
  final _tenderedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTable = widget.initialTable;
  }

  @override
  void dispose() {
    _tenderedController.dispose();
    super.dispose();
  }

  double? get _tenderedAmount => double.tryParse(_tenderedController.text);

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isCompleted =
        checkoutState is CheckoutSuccess || checkoutState is CheckoutHeld;

    // Clears the cart exactly once, via the existing CartController ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â not
    // duplicated clearing logic ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â the moment an order actually succeeds.
    ref.listen<CheckoutState>(checkoutControllerProvider, (previous, next) {
      if ((next is CheckoutSuccess && previous is! CheckoutSuccess) ||
          (next is CheckoutHeld && previous is! CheckoutHeld)) {
        ref.read(cartControllerProvider.notifier).clear();

        if (context.mounted) {
          context.go('/pos/select-table');
        }
      }
    });

    return PopScope(
      // Every other state (idle/submitting/error) keeps the default pop
      // behavior ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â back button/gesture/AppBar arrow returns to /pos,
      // satisfying "Checkout ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ POS" unchanged. Only the success state
      // intercepts it: popping normally would land back on /pos showing
      // the now-emptied cart, which isn't a meaningful place to return
      // to once an order is already confirmed.
      canPop: !isCompleted,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: switch (checkoutState) {
          CheckoutSuccess(:final confirmation) => _CheckoutSuccessView(confirmation: confirmation),
          _ => _CheckoutForm(
              cart: cart,
              paymentMethod: _paymentMethod,              selectedTable: _selectedTable,
              onTableChanged: (table) => setState(() => _selectedTable = table),
              onPaymentMethodChanged: (method) => setState(() => _paymentMethod = method),
              tenderedController: _tenderedController,
              tenderedAmount: _tenderedAmount,
              canSaveOrder: cart.items.isNotEmpty &&
                  _selectedTable != null &&
                  checkoutState is! CheckoutSubmitting,
              onTenderedChanged: () => setState(() {}),
              isSubmitting: checkoutState is CheckoutSubmitting,
              errorMessage: checkoutState is CheckoutError ? checkoutState.message : null,
              onConfirm: () {
                ref.read(checkoutControllerProvider.notifier).submit(
                      items: cart.items,
                      paymentMethod: _paymentMethod,
                      orderType: 'dine_in',
                      tableId: _selectedTable?.id,
                      tendered: _paymentMethod == 'cash' ? _tenderedAmount : null,
                      discountTotal: cart.discountTotal,
                    );
              },
              onHold: () {
                ref.read(checkoutControllerProvider.notifier).hold(
                      items: cart.items,
                      orderType: 'dine_in',
                      tableId: _selectedTable!.id,
                      discountTotal: cart.discountTotal,
                    );
              },
            ),
        },
      ),
    );
  }
}

class _CheckoutForm extends StatelessWidget {
  const _CheckoutForm({
    required this.cart,
    required this.paymentMethod,
required this.selectedTable,
    required this.onTableChanged,
required this.onPaymentMethodChanged,
    required this.tenderedController,
    required this.tenderedAmount,
    required this.canSaveOrder,
    required this.onTenderedChanged,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onConfirm,
    required this.onHold,
  });

  final CartState cart;
  final String paymentMethod;
final PosTable? selectedTable;
  final ValueChanged<PosTable> onTableChanged;
final ValueChanged<String> onPaymentMethodChanged;
  final TextEditingController tenderedController;
  final double? tenderedAmount;
  final bool canSaveOrder;
  final VoidCallback onTenderedChanged;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onConfirm;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final change = (paymentMethod == 'cash' && tenderedAmount != null) ? tenderedAmount! - cart.total : null;
    final canConfirm = !isSubmitting &&
        cart.items.isNotEmpty && (selectedTable != null) &&
        (paymentMethod != 'cash' || (tenderedAmount != null && tenderedAmount! >= cart.total));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],
          Text('Order Summary', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final item in cart.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.variant != null
                                  ? '${item.product.name} ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ${item.variant!.name}'
                                  : item.product.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${item.quantity} x ${currency.format(item.unitPrice)}'),
                        ],
                      ),
                    ),
                  Divider(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _SummaryRow(label: 'Subtotal', value: currency.format(cart.subtotal)),
                  if (cart.discountTotal > 0)
                    _SummaryRow(label: 'Discount', value: '- ${currency.format(cart.discountTotal)}'),
                  _SummaryRow(label: 'Total', value: currency.format(cart.total), emphasize: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (selectedTable != null) ...[
            const SizedBox(height: 24),
            Text('Table', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.table_restaurant,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${selectedTable!.name} - ${selectedTable!.capacity} seats',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),

                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Payment Method', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
              ButtonSegment(value: 'card', label: Text('Card'), icon: Icon(Icons.credit_card)),
              ButtonSegment(value: 'qr', label: Text('QR'), icon: Icon(Icons.qr_code)),
            ],
            selected: {paymentMethod},
            onSelectionChanged: isSubmitting ? null : (selection) => onPaymentMethodChanged(selection.first),
          ),
          if (paymentMethod == 'cash') ...[
            const SizedBox(height: 16),
            TextField(
              controller: tenderedController,
              enabled: !isSubmitting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount Received',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onTenderedChanged(),
            ),
            const SizedBox(height: 12),
            Text(
              'Quick Amount',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in {
                  cart.total,
                  15.0,
                  20.0,
                  50.0,
                })
                  OutlinedButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            tenderedController.text =
                                amount.toStringAsFixed(2);
                            onTenderedChanged();
                          },
                    child: Text(currency.format(amount)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              change == null
                  ? 'Enter the amount received'
                  : change >= 0
                      ? 'Change due: ${currency.format(change)}'
                      : 'Short by ${currency.format(-change)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: (change != null && change < 0) ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (selectedTable != null) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: canSaveOrder ? onHold : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save Order'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canConfirm ? onConfirm : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Confirm Payment'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSuccessView extends StatelessWidget {
  const _CheckoutSuccessView({required this.confirmation});

  final OrderConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Payment Confirmed', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Order #${confirmation.orderId}', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                currency.format(confirmation.total),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (confirmation.changeDue != null) ...[
                const SizedBox(height: 4),
                Text('Change due: ${currency.format(confirmation.changeDue)}'),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.go('/pos'),
                child: const Text('New Order'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}






































