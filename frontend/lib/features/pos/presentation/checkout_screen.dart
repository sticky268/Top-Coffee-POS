import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/printer/printer_service.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_models.dart';
import '../../orders/application/orders_list_controller.dart';
import '../../settings/data/receipt_settings.dart';
import '../application/cart_controller.dart';
import '../application/cart_state.dart';
import '../application/checkout_controller.dart';
import '../application/checkout_state.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

/// Order review + payment screen, reached via the cart's "Review Order" /
/// "Checkout" action. Reads the cart at build time; on a successful order,
/// clears the cart via the existing CartController (no new cart-clearing
/// logic here) and shows a confirmation.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, this.initialTable});

  final PosTable? initialTable;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _SplitPaymentLine {
  _SplitPaymentLine({
    this.method = 'cash',
    String amount = '',
    String tendered = '',
  }) : amountController = TextEditingController(text: amount),
       tenderedController = TextEditingController(text: tendered);

  String method;
  final TextEditingController amountController;
  final TextEditingController tenderedController;

  void dispose() {
    amountController.dispose();
    tenderedController.dispose();
  }

  Map<String, dynamic> toJson() {
    final amount = double.tryParse(amountController.text) ?? 0;

    return {
      'method': method,
      'amount': amount,
      if (method == 'cash')
        'tendered': double.tryParse(tenderedController.text) ?? 0,
    };
  }
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _paymentMethod = 'cash';
  String _orderType = 'takeaway';
  PosTable? _selectedTable;
  Customer? _selectedCustomer;
  final _tenderedController = TextEditingController();
  final List<_SplitPaymentLine> _splitPayments = [
    _SplitPaymentLine(method: 'cash'),
    _SplitPaymentLine(method: 'qr'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTable = widget.initialTable;
  }

  @override
  void dispose() {
    _tenderedController.dispose();

    for (final payment in _splitPayments) {
      payment.dispose();
    }

    super.dispose();
  }

  double? get _tenderedAmount => double.tryParse(_tenderedController.text);

  Future<void> _openCustomerPicker() async {
    final repository = ref.read(customersRepositoryProvider);
    final branchId = ref.read(currentBranchProvider)?.id;

    final customer = await showModalBottomSheet<Customer?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerPickerSheet(
        repository: repository,
        branchId: branchId,
        selectedCustomer: _selectedCustomer,
      ),
    );

    if (!mounted) return;

    setState(() {
      _selectedCustomer = customer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isCompleted =
        checkoutState is CheckoutSuccess || checkoutState is CheckoutHeld;

    // Clears the cart exactly once, via the existing CartController ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â not
    // duplicated clearing logic ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â the moment an order actually succeeds.
    ref.listen<CheckoutState>(checkoutControllerProvider, (previous, next) {
      if (next is CheckoutSuccess && previous is! CheckoutSuccess) {
        ref.read(cartControllerProvider.notifier).clear();
        // Include newly completed orders in order history immediately.
        ref.read(ordersListControllerProvider.notifier).refresh();
        return;
      }

      if (next is CheckoutHeld && previous is! CheckoutHeld) {
        ref.read(cartControllerProvider.notifier).clear();
        // Refresh order history as soon as the new held order is saved.
        ref.read(ordersListControllerProvider.notifier).refresh();

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
          CheckoutSuccess(:final confirmation) => _CheckoutSuccessView(
            confirmation: confirmation,
          ),
          _ => _CheckoutForm(
            cart: cart,
            orderType: _orderType,
            paymentMethod: _paymentMethod,
            selectedTable: _selectedTable,
            selectedCustomer: _selectedCustomer,
            onCustomerChanged: (customer) =>
                setState(() => _selectedCustomer = customer),
            onCustomerTap: _openCustomerPicker,
            splitPayments: _splitPayments,
            onTableChanged: (table) => setState(() => _selectedTable = table),
            onOrderTypeChanged: (type) {
              setState(() {
                _orderType = type;

                if (type == 'takeaway') {
                  _selectedTable = null;
                }
              });
            },
            onPaymentMethodChanged: (method) =>
                setState(() => _paymentMethod = method),
            tenderedController: _tenderedController,
            tenderedAmount: _tenderedAmount,
            canSaveOrder:
                cart.items.isNotEmpty &&
                _selectedTable != null &&
                checkoutState is! CheckoutSubmitting,
            onTenderedChanged: () => setState(() {}),
            isSubmitting: checkoutState is CheckoutSubmitting,
            errorMessage: checkoutState is CheckoutError
                ? checkoutState.message
                : null,
            onConfirm: () {
              ref
                  .read(checkoutControllerProvider.notifier)
                  .submit(
                    items: cart.items,
                    paymentMethod: _paymentMethod,
                    orderType: _orderType,
                    tableId: _selectedTable?.id,
                    tendered: _paymentMethod == 'cash' ? _tenderedAmount : null,
                    splitPayments: _paymentMethod == 'split'
                        ? _splitPayments
                              .map((payment) => payment.toJson())
                              .toList()
                        : null,
                    discountTotal: cart.discountTotal,
                    customerId: _selectedCustomer?.id,
                  );
            },
            onHold: () {
              ref
                  .read(checkoutControllerProvider.notifier)
                  .hold(
                    items: cart.items,
                    orderType: 'dine_in',
                    tableId: _selectedTable!.id,
                    discountTotal: cart.discountTotal,
                    customerId: _selectedCustomer?.id,
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
    required this.orderType,
    required this.paymentMethod,
    required this.selectedTable,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.onCustomerTap,
    required this.splitPayments,
    required this.onTableChanged,
    required this.onOrderTypeChanged,
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
  final String orderType;
  final String paymentMethod;
  final PosTable? selectedTable;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final VoidCallback onCustomerTap;
  final List<_SplitPaymentLine> splitPayments;
  final ValueChanged<PosTable> onTableChanged;
  final ValueChanged<String> onOrderTypeChanged;
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
    final change = (paymentMethod == 'cash' && tenderedAmount != null)
        ? tenderedAmount! - cart.total
        : null;
    final splitTotal = splitPayments.fold<double>(
      0,
      (sum, payment) =>
          sum + (double.tryParse(payment.amountController.text) ?? 0),
    );

    final splitValid =
        splitPayments.length >= 2 &&
        splitPayments.every((payment) {
          final amount = double.tryParse(payment.amountController.text) ?? 0;
          if (amount <= 0) return false;

          if (payment.method == 'cash') {
            final tendered = double.tryParse(payment.tenderedController.text);
            return tendered != null && tendered >= amount;
          }

          return true;
        }) &&
        (splitTotal - cart.total).abs() < 0.01;

    final canConfirm =
        !isSubmitting &&
        cart.items.isNotEmpty &&
        (orderType == 'takeaway' || selectedTable != null) &&
        (paymentMethod == 'split'
            ? splitValid
            : paymentMethod != 'cash' ||
                  tenderedAmount == null ||
                  tenderedAmount! >= cart.total);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],
          Text(
            'Review Order',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (orderType == 'dine_in' && selectedTable != null)
            Text(
              ' · Dine-in',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (orderType == 'takeaway')
            Text(
              'Takeaway order',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              'Dine-in order',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Order Type',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'takeaway',
                  label: Text('Takeaway'),
                  icon: Icon(Icons.shopping_bag_outlined),
                ),
                ButtonSegment<String>(
                  value: 'dine_in',
                  label: Text('Dine-in'),
                  icon: Icon(Icons.table_restaurant_outlined),
                ),
              ],
              selected: {orderType},
              onSelectionChanged: isSubmitting
                  ? null
                  : (selection) => onOrderTypeChanged(selection.first),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Customer',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          pos_ui.ActionSurface(
            onTap: isSubmitting ? null : onCustomerTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      selectedCustomer == null
                          ? Icons.person_outline
                          : Icons.person,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedCustomer?.name ?? 'Walk-in Customer',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (selectedCustomer?.phone != null &&
                            selectedCustomer!.phone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            selectedCustomer!.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else if (selectedCustomer == null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'No customer selected',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ORDER',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  for (final item in cart.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${item.quantity}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.name,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.variant != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    item.variant!.name,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text(
                                  currency.format(item.unitPrice),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            currency.format(item.unitPrice * item.quantity),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Divider(color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  _SummaryRow(
                    label: 'Subtotal',
                    value: currency.format(cart.subtotal),
                  ),
                  if (cart.discountTotal > 0)
                    _SummaryRow(
                      label: 'Discount',
                      value: '- ${currency.format(cart.discountTotal)}',
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        currency.format(cart.total),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (orderType == 'dine_in' && selectedTable != null) ...[
            const SizedBox(height: 8),
            Text(
              'TABLE',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.table_restaurant_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedTable!.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Dine-in · ${selectedTable!.capacity} seats',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'PAYMENT',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how the customer is paying',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cash',
                label: Text('Cash'),
                icon: Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: 'card',
                label: Text('Card'),
                icon: Icon(Icons.credit_card_outlined),
              ),
              ButtonSegment(
                value: 'qr',
                label: Text('QR'),
                icon: Icon(Icons.qr_code_2_outlined),
              ),
              ButtonSegment(
                value: 'split',
                label: Text('Split'),
                icon: Icon(Icons.call_split_outlined),
              ),
            ],
            selected: {paymentMethod},
            onSelectionChanged: isSubmitting
                ? null
                : (selection) => onPaymentMethodChanged(selection.first),
          ),
          const SizedBox(height: 16),
          if (paymentMethod == 'split') ...[
            Card(
              elevation: 1,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Split payment',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Divide the total across multiple payment methods.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var index = 0; index < splitPayments.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: splitPayments[index].method,
                                      decoration: InputDecoration(
                                        labelText: 'Method',
                                        filled: true,
                                        fillColor: theme
                                            .colorScheme
                                            .surfaceContainerLowest,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'cash',
                                          child: Text('Cash'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'card',
                                          child: Text('Card'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'qr',
                                          child: Text('QR'),
                                        ),
                                      ],
                                      onChanged: isSubmitting
                                          ? null
                                          : (method) {
                                              if (method == null) return;
                                              splitPayments[index].method =
                                                  method;
                                              onTenderedChanged();
                                            },
                                    ),
                                  ),
                                  if (splitPayments.length > 2) ...[
                                    const SizedBox(width: 8),
                                    pos_ui.IconButton(
                                      tooltip: 'Remove payment',
                                      onPressed: isSubmitting
                                          ? null
                                          : () {
                                              splitPayments[index].dispose();
                                              splitPayments.removeAt(index);
                                              onTenderedChanged();
                                            },
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller:
                                    splitPayments[index].amountController,
                                enabled: !isSubmitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Amount',
                                  prefixText: '\$ ',
                                  filled: true,
                                  fillColor:
                                      theme.colorScheme.surfaceContainerLowest,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) => onTenderedChanged(),
                              ),
                              if (splitPayments[index].method == 'cash') ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller:
                                      splitPayments[index].tenderedController,
                                  enabled: !isSubmitting,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Cash received',
                                    prefixText: '\$ ',
                                    filled: true,
                                    fillColor: theme
                                        .colorScheme
                                        .surfaceContainerLowest,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onChanged: (_) => onTenderedChanged(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    pos_ui.OutlinedButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () {
                              splitPayments.add(
                                _SplitPaymentLine(method: 'qr'),
                              );
                              onTenderedChanged();
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Add payment method'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SummaryRow(
                      label: 'Paid',
                      value: currency.format(splitTotal),
                    ),
                    _SummaryRow(
                      label: splitTotal >= cart.total ? 'Change' : 'Remaining',
                      value: currency.format(
                        splitTotal >= cart.total
                            ? splitTotal - cart.total
                            : cart.total - splitTotal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (paymentMethod == 'cash') ...[
            Card(
              elevation: 1,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: tenderedController,
                      enabled: !isSubmitting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount received',
                        prefixText: '\$ ',
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => onTenderedChanged(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Quick amounts',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final amount in {cart.total, 15.0, 20.0, 50.0})
                          pos_ui.OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () {
                                    tenderedController.text = amount
                                        .toStringAsFixed(2);
                                    onTenderedChanged();
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(currency.format(amount)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            change == null
                                ? 'Change'
                                : change >= 0
                                ? 'Change'
                                : 'Short by',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            change == null
                                ? '—'
                                : currency.format(change.abs()),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: change != null && change < 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          if (selectedTable != null)
            pos_ui.OutlinedButton(
              onPressed: canSaveOrder ? onHold : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide.none,
                backgroundColor: theme.colorScheme.surfaceContainerLow,
                foregroundColor: theme.colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Save for Later'),
            ),
          if (selectedTable != null) const SizedBox(height: 8),
          pos_ui.PosActionButton(
            onPressed: canConfirm ? onConfirm : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            isLoading: isSubmitting,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Confirm & Pay',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  currency.format(cart.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSuccessView extends ConsumerStatefulWidget {
  const _CheckoutSuccessView({required this.confirmation});

  final OrderConfirmation confirmation;

  @override
  ConsumerState<_CheckoutSuccessView> createState() =>
      _CheckoutSuccessViewState();
}

class _CheckoutSuccessViewState extends ConsumerState<_CheckoutSuccessView> {
  bool _isPrinting = false;

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

  Future<void> _printReceipt() async {
    if (_isPrinting) {
      return;
    }

    final settings = await ReceiptSettings.load();

    if (!settings.printerEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt printing is disabled in Settings.'),
          ),
        );
      }
      return;
    }

    if (settings.printerIpAddress.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer IP address is not configured.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isPrinting = true;
    });

    final printerService = PrinterService();

    try {
      final receipt = await ref
          .read(posRepositoryProvider)
          .getOrderReceipt(orderId: widget.confirmation.orderId);

      debugPrint(
        '🧾 PRINT RECEIPT: order=${receipt.orderId}, '
        'subtotal=${receipt.subtotal}, '
        'discount=${receipt.discountTotal}, '
        'total=${receipt.total}',
      );
      await printerService.connect(settings.printerIpAddress);
      await printerService.printReceipt(receipt);
      await printerService.disconnect();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt printed successfully.')),
      );
    } catch (e) {
      try {
        await printerService.disconnect();
      } catch (_) {
        // Ignore disconnect errors after a failed print.
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to print receipt: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
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

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TOTAL PAID',
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currency.format(widget.confirmation.total),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _paymentLabel(payment.method),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                currency.format(payment.amount),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),

                          if (payment.method == 'cash' &&
                              payment.tendered != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Cash received',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  currency.format(payment.tendered),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          if (payment.changeDue != null &&
                              payment.changeDue! > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Change',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  currency.format(payment.changeDue),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          if (payment != payments.last)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1),
                            ),
                        ],
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _paymentLabel(
                                  widget.confirmation.paymentMethod,
                                ),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              currency.format(widget.confirmation.total),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),

                        if (widget.confirmation.tendered != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Cash received',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                currency.format(widget.confirmation.tendered),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],

                        if (widget.confirmation.changeDue != null &&
                            widget.confirmation.changeDue! > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Change',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                currency.format(widget.confirmation.changeDue),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                pos_ui.OutlinedButton.icon(
                  onPressed: _isPrinting ? null : _printReceipt,
                  isLoading: _isPrinting,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_isPrinting ? 'Printing...' : 'Print Receipt'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
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

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.repository, required this.branchId});

  final CustomersRepository repository;
  final int? branchId;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final customer = await widget.repository.createCustomer(
        name: name,
        phone: phone.isEmpty ? null : phone,
        branchId: widget.branchId,
      );

      if (!mounted) return;

      Navigator.of(context).pop(customer);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create customer.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Customer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            enabled: !_isSaving,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Customer name',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            enabled: !_isSaving,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Phone',
              hintText: 'Phone number',
            ),
          ),
        ],
      ),
      actions: [
        pos_ui.SecondaryButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        pos_ui.PrimaryButton(
          onPressed: _isSaving ? null : _save,
          isLoading: _isSaving,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({
    required this.repository,
    required this.branchId,
    required this.selectedCustomer,
  });

  final CustomersRepository repository;
  final int? branchId;
  final Customer? selectedCustomer;

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.getCustomers(
        search: _searchController.text.trim(),
        branchId: widget.branchId,
      );

      if (!mounted) return;

      setState(() {
        _customers = result.data;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load customers.';
      });
    }
  }

  Future<void> _addCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (dialogContext) {
        return _AddCustomerDialog(
          repository: widget.repository,
          branchId: widget.branchId,
        );
      },
    );

    if (!mounted || customer == null) return;

    Navigator.of(context).pop(customer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select Customer',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  pos_ui.IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadCustomers(),
                decoration: InputDecoration(
                  hintText: 'Search name or phone',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: pos_ui.IconButton(
                    onPressed: _loadCustomers,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: pos_ui.OutlinedButton.icon(
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Customer'),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 16),

              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.person_outline),
                ),
                title: const Text(
                  'Walk-in Customer',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('No customer selected'),
                trailing: widget.selectedCustomer == null
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(),
              ),

              const SizedBox(height: 8),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                    ? Center(
                        child: Text(
                          'No customers found.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final isSelected =
                              widget.selectedCustomer?.id == customer.id;

                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                customer.name.isNotEmpty
                                    ? customer.name[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(
                              customer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle:
                                customer.phone == null ||
                                    customer.phone!.isEmpty
                                ? null
                                : Text(customer.phone!),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(customer),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
