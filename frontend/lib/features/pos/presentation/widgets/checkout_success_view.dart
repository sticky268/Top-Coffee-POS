import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../../core/widgets/cash_drawer_status.dart';
import '../../../../core/widgets/receipt_action_buttons.dart';
import '../../domain/pos_models.dart';
import 'checkout_summary.dart';

class CheckoutSuccessView extends ConsumerStatefulWidget {
  const CheckoutSuccessView({
    super.key,
    required this.confirmation,
    this.autoPrint = false,
  });

  final OrderConfirmation confirmation;
  final bool autoPrint;

  @override
  ConsumerState<CheckoutSuccessView> createState() =>
      _CheckoutSuccessViewState();
}

class _CheckoutSuccessViewState extends ConsumerState<CheckoutSuccessView> {
  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'qr':
        return 'QR';
      case 'split':
        return 'Split payment';
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final payments = widget.confirmation.payments;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 42,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Payment Successful',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Order #${widget.confirmation.displayOrderNumber}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                CashDrawerStatus(result: widget.confirmation.cashDrawerResult),
                CheckoutTotalCard(
                  label: 'Total paid',
                  value: currency.format(widget.confirmation.total),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAYMENT',
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (payments.length > 1) ...[
                        for (final payment in payments) ...[
                          CheckoutAmountRow(
                            label: _paymentLabel(payment.method),
                            value: currency.format(payment.amount),
                          ),
                          if (payment.method == 'cash' &&
                              payment.tendered != null) ...[
                            const SizedBox(height: 4),
                            CheckoutAmountRow(
                              label: 'Cash received',
                              value: currency.format(payment.tendered),
                            ),
                          ],
                          if (payment.changeDue != null &&
                              payment.changeDue! > 0) ...[
                            const SizedBox(height: 4),
                            CheckoutAmountRow(
                              label: 'Change',
                              value: currency.format(payment.changeDue),
                            ),
                          ],
                          if (payment != payments.last)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1),
                            ),
                        ],
                      ] else ...[
                        CheckoutAmountRow(
                          label: _paymentLabel(
                            widget.confirmation.paymentMethod,
                          ),
                          value: currency.format(widget.confirmation.total),
                        ),
                        if (widget.confirmation.tendered != null) ...[
                          const SizedBox(height: 8),
                          CheckoutAmountRow(
                            label: 'Cash received',
                            value: currency.format(
                              widget.confirmation.tendered,
                            ),
                          ),
                        ],
                        if (widget.confirmation.changeDue != null &&
                            widget.confirmation.changeDue! > 0) ...[
                          const SizedBox(height: 8),
                          CheckoutAmountRow(
                            label: 'Change',
                            value: currency.format(
                              widget.confirmation.changeDue,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ReceiptActionButtons(
                  orderId: widget.confirmation.orderId,
                  autoPrint: widget.autoPrint,
                ),
                const SizedBox(height: 16),
                pos_ui.PosActionButton(
                  onPressed: () => context.go('/pos/select-table'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'New Order',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                pos_ui.SecondaryButton(
                  onPressed: () => context.go('/home'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Back to Dashboard'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
