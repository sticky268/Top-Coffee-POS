import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/receipt/customer_bill.dart';
import '../../../core/receipt/last_receipt_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../core/widgets/receipt_action_buttons.dart';
import '../../../core/widgets/cash_drawer_status.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_models.dart';
import '../../orders/application/orders_list_controller.dart';
import '../application/cart_controller.dart';
import '../application/cart_state.dart';
import '../application/checkout_controller.dart';
import '../application/checkout_state.dart';
import '../domain/pos_models.dart';
import 'widgets/checkout_summary.dart';
import 'widgets/checkout_actions.dart';
import 'widgets/cash_quick_amounts.dart';
import '../../../core/config/till_currency.dart';

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
  })  : amountController = TextEditingController(text: amount),
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
  bool _printAfterSale = false;
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
    _selectedTable =
        widget.initialTable ?? ref.read(cartControllerProvider).table;
    if (_selectedTable != null) {
      _orderType = 'dine_in';
    }
    final auth = ref.read(authControllerProvider);
    final methods = auth is AuthAuthenticated
        ? auth.user.allowedPaymentMethods
        : const ['cash', 'card', 'qr'];
    if (methods.isNotEmpty) {
      _paymentMethod = methods.first;
      _splitPayments[0].method = methods.first;
      _splitPayments[1].method =
          methods.length > 1 ? methods[1] : methods.first;
    }
  }

  @override
  void dispose() {
    _tenderedController.dispose();

    for (final payment in _splitPayments) {
      payment.dispose();
    }

    super.dispose();
  }

  Future<void> _chooseTable() async {
    final table = await context.push<PosTable>('/pos/select-table?select=true');
    if (!mounted || table == null) return;
    ref.read(cartControllerProvider.notifier).selectTable(table);
    setState(() {
      _selectedTable = table;
      _orderType = 'dine_in';
    });
  }

  double? get _tenderedAmount => double.tryParse(_tenderedController.text);

  Future<bool> _confirmSeparateSale(String uuid) async {
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Matching sale awaiting confirmation'),
        content: Text(
          'A matching order is already saved on this device. Check it before '
          'collecting payment again. Continue only for a separate sale.\n\n'
          'Reference: $uuid',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('review'),
            child: const Text('View Pending Orders'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('separate'),
            child: const Text('Confirm Separate Sale'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (answer == 'review') context.go('/pending-orders');
    return answer == 'separate';
  }

  Future<void> _startAnotherOrderAfterQueue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start another order?'),
        content: const Text(
          'This payment is still awaiting server confirmation. Starting an '
          'identical order may charge the customer twice. Only continue when '
          'this is a separate sale.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Check Pending Order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start Separate Sale'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) context.go('/pos');
  }

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
    final currentBranch = ref.watch(currentBranchProvider);
    final authState = ref.watch(authControllerProvider);
    final cashierName =
        authState is AuthAuthenticated ? authState.user.name : null;
    final isCompleted = checkoutState is CheckoutSuccess ||
        checkoutState is CheckoutHeld ||
        checkoutState is CheckoutQueued;

    // Clears the cart exactly once, via the existing CartController ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â not
    // duplicated clearing logic ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â the moment an order actually succeeds.
    ref.listen<CheckoutState>(checkoutControllerProvider, (previous, next) {
      if (next is CheckoutQueued && previous is! CheckoutQueued) {
        ref.read(cartControllerProvider.notifier).clear();
        return;
      }
      if (next is CheckoutSuccess && previous is! CheckoutSuccess) {
        ref.read(cartControllerProvider.notifier).clear();
        // Include newly completed orders in order history immediately.
        ref.read(ordersListControllerProvider.notifier).refresh();
        ref.invalidate(lastCompletedOrderProvider);
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
        appBar: AppBar(title: const Text('Review Order')),
        body: switch (checkoutState) {
          CheckoutQueued(:final uuid) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text('Order saved on this device'),
                    const SizedBox(height: 8),
                    const Text(
                      'Waiting for server confirmation. Check Pending Orders before collecting another payment for this sale.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text('Reference: $uuid', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    pos_ui.PrimaryButton(
                      onPressed: () => context.go('/pending-orders'),
                      child: const Text('View Pending Orders'),
                    ),
                    pos_ui.SecondaryButton(
                      onPressed: _startAnotherOrderAfterQueue,
                      child: const Text('Start Another Order'),
                    ),
                  ],
                ),
              ),
            ),
          CheckoutSuccess(:final confirmation) => _CheckoutSuccessView(
              confirmation: confirmation,
              autoPrint: _printAfterSale,
            ),
          _ => _CheckoutForm(
              cart: cart,
              orderType: _orderType,
              branchName: currentBranch?.name,
              branchCode: currentBranch?.code,
              cashierName: cashierName,
              allowedPaymentMethods: authState is AuthAuthenticated
                  ? authState.user.allowedPaymentMethods
                  : const ['cash', 'card', 'qr'],
              paymentMethod: _paymentMethod,
              selectedTable: _selectedTable,
              selectedCustomer: _selectedCustomer,
              onCustomerChanged: (customer) =>
                  setState(() => _selectedCustomer = customer),
              onCustomerTap: _openCustomerPicker,
              splitPayments: _splitPayments,
              onTableChanged: (table) => setState(() => _selectedTable = table),
              onChooseTable: _chooseTable,
              onOrderTypeChanged: (type) {
                setState(() {
                  _orderType = type;

                  if (type == 'takeaway') {
                    _selectedTable = null;
                    ref.read(cartControllerProvider.notifier).selectTable(null);
                  }
                });
                if (type == 'dine_in' && _selectedTable == null) _chooseTable();
              },
              onPaymentMethodChanged: (method) =>
                  setState(() => _paymentMethod = method),
              tenderedController: _tenderedController,
              tenderedAmount: _tenderedAmount,
              canSaveOrder: cart.items.isNotEmpty &&
                  _selectedTable != null &&
                  checkoutState is! CheckoutSubmitting,
              onTenderedChanged: () => setState(() {}),
              isSubmitting: checkoutState is CheckoutSubmitting,
              errorMessage:
                  checkoutState is CheckoutError ? checkoutState.message : null,
              onConfirm: (printReceipt) {
                if (ref.read(checkoutControllerProvider)
                    is CheckoutSubmitting) {
                  return;
                }
                _printAfterSale = printReceipt;
                ref.read(checkoutControllerProvider.notifier).submit(
                      confirmSeparateSale: _confirmSeparateSale,
                      items: cart.items,
                      paymentMethod: _paymentMethod,
                      orderType: _orderType,
                      tableId: _selectedTable?.id,
                      tendered:
                          _paymentMethod == 'cash' ? _tenderedAmount : null,
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
                ref.read(checkoutControllerProvider.notifier).hold(
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
    required this.branchName,
    required this.branchCode,
    required this.cashierName,
    this.allowedPaymentMethods = const ['cash', 'card', 'qr'],
    required this.paymentMethod,
    required this.selectedTable,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.onCustomerTap,
    required this.splitPayments,
    required this.onTableChanged,
    required this.onChooseTable,
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
  final String? branchName;
  final String? branchCode;
  final String? cashierName;
  final List<String> allowedPaymentMethods;
  final String paymentMethod;
  final PosTable? selectedTable;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final VoidCallback onCustomerTap;
  final List<_SplitPaymentLine> splitPayments;
  final ValueChanged<PosTable> onTableChanged;
  final VoidCallback onChooseTable;
  final ValueChanged<String> onOrderTypeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final TextEditingController tenderedController;
  final double? tenderedAmount;
  final bool canSaveOrder;
  final VoidCallback onTenderedChanged;
  final bool isSubmitting;
  final String? errorMessage;
  final ValueChanged<bool> onConfirm;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');
    final change = (paymentMethod == 'cash' &&
            tenderedAmount != null &&
            tenderedAmount!.isFinite)
        ? tenderedAmount! - cart.total
        : null;
    final splitTotal = splitPayments.fold<double>(
      0,
      (sum, payment) =>
          sum + (double.tryParse(payment.amountController.text) ?? 0),
    );

    final splitValid = splitPayments.length >= 2 &&
        splitPayments.every((payment) {
          final amount = double.tryParse(payment.amountController.text) ?? 0;
          if (!amount.isFinite || amount <= 0) return false;

          if (payment.method == 'cash') {
            final tendered = double.tryParse(payment.tenderedController.text);
            return tendered != null && tendered.isFinite && tendered >= amount;
          }

          return true;
        }) &&
        splitTotal.isFinite &&
        (splitTotal - cart.total).abs() < 0.01;

    // Read-only preview: allocated amounts are not cash received.
    final cashPortions =
        splitPayments.where((payment) => payment.method == 'cash').toList();
    final cashChangeReady = cashPortions.isNotEmpty &&
        cashPortions.every((payment) {
          final amount = double.tryParse(payment.amountController.text);
          final received = double.tryParse(payment.tenderedController.text);
          return amount != null &&
              amount.isFinite &&
              amount > 0 &&
              received != null &&
              received.isFinite &&
              received >= amount;
        });
    final splitCashChange = cashChangeReady
        ? cashPortions.fold<double>(
            0,
            (sum, payment) =>
                sum +
                double.parse(payment.tenderedController.text) -
                double.parse(payment.amountController.text),
          )
        : null;

    final canConfirm = !isSubmitting &&
        (allowedPaymentMethods.contains(paymentMethod) ||
            (paymentMethod == 'split' &&
                allowedPaymentMethods.toSet().length > 1)) &&
        cart.items.isNotEmpty &&
        (orderType == 'takeaway' || selectedTable != null) &&
        (paymentMethod == 'split'
            ? splitValid
            : paymentMethod != 'cash' ||
                tenderedController.text.trim().isEmpty ||
                (tenderedAmount != null &&
                    tenderedAmount!.isFinite &&
                    tenderedAmount! >= cart.total));

    final customerBill = CustomerBill(
      orderType: orderType,
      branchName: branchName,
      branchCode: branchCode,
      cashierName: cashierName,
      tableName: selectedTable?.name,
      subtotal: cart.subtotal,
      discountTotal: cart.discountTotal,
      total: cart.total,
      items: cart.items
          .map(
            (item) => CustomerBillLine(
              productName: item.product.name,
              variantName: item.variant?.name,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      createdAt: DateTime.now(),
    );

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: LayoutBuilder(
            builder: (context, viewport) => Column(
              children: [
                Expanded(
                  child: ListView(
                    key: const ValueKey('checkout-review-scroll'),
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
                          'Dine-in order',
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
                      CheckoutChoiceSelector(
                        choices: const [
                          CheckoutChoice(
                            'takeaway',
                            'Takeaway',
                            Icons.shopping_bag_outlined,
                          ),
                          CheckoutChoice(
                            'dine_in',
                            'Dine-in',
                            Icons.table_restaurant_outlined,
                          ),
                        ],
                        selected: orderType,
                        enabled: !isSubmitting,
                        onChanged: onOrderTypeChanged,
                      ),
                      if (orderType == 'dine_in') ...[
                        const SizedBox(height: 8),
                        pos_ui.SecondaryButton.icon(
                          onPressed: isSubmitting ? null : onChooseTable,
                          icon: const Icon(Icons.table_restaurant),
                          label: Text(selectedTable == null
                              ? 'Select Table'
                              : 'Change ${selectedTable!.name}'),
                        ),
                      ],
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
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
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
                                      selectedCustomer?.name ??
                                          'Walk-in Customer',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (selectedCustomer?.phone != null &&
                                        selectedCustomer!
                                            .phone!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedCustomer!.phone!,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ] else if (selectedCustomer == null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'No customer selected',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
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
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Column(
                            children: [
                              for (final item in cart.items)
                                CheckoutOrderLine(
                                  title: item.product.name,
                                  variant: item.variant?.name,
                                  quantity: item.quantity,
                                  unitPrice: currency.format(item.unitPrice),
                                  lineTotal: currency.format(
                                    item.unitPrice * item.quantity,
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
                                  value:
                                      '- ${currency.format(cart.discountTotal)}',
                                ),
                              const SizedBox(height: 8),
                              CheckoutTotalCard(
                                  value: currency.format(cart.total)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        elevation: 1,
                        color: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: BillActionButtons(
                            bill: customerBill,
                            showHeading: true,
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
                            side: BorderSide(
                                color: theme.colorScheme.outlineVariant),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedTable!.name,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Dine-in · ${selectedTable!.capacity} seats',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
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
                      CheckoutChoiceSelector(
                        choices: [
                          if (allowedPaymentMethods.contains('cash'))
                            const CheckoutChoice(
                                'cash', 'Cash', Icons.payments_outlined),
                          if (allowedPaymentMethods.contains('card'))
                            const CheckoutChoice(
                                'card', 'Card', Icons.credit_card_outlined),
                          if (allowedPaymentMethods.contains('qr'))
                            const CheckoutChoice(
                                'qr', 'QR', Icons.qr_code_2_outlined),
                          if (allowedPaymentMethods.toSet().length > 1)
                            const CheckoutChoice(
                                'split', 'Split', Icons.call_split_outlined),
                        ],
                        selected: paymentMethod,
                        enabled: !isSubmitting,
                        onChanged: onPaymentMethodChanged,
                      ),
                      const SizedBox(height: 16),
                      if (paymentMethod == 'split') ...[
                        Card(
                          elevation: 1,
                          color: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                                color: theme.colorScheme.outlineVariant),
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
                                for (var index = 0;
                                    index < splitPayments.length;
                                    index++)
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
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  initialValue:
                                                      splitPayments[index]
                                                          .method,
                                                  decoration: InputDecoration(
                                                    labelText: 'Method',
                                                    filled: true,
                                                    fillColor: theme.colorScheme
                                                        .surfaceContainerLowest,
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      borderSide:
                                                          BorderSide.none,
                                                    ),
                                                  ),
                                                  items: [
                                                    if (allowedPaymentMethods
                                                        .contains('cash'))
                                                      const DropdownMenuItem(
                                                        value: 'cash',
                                                        child: Text('Cash'),
                                                      ),
                                                    if (allowedPaymentMethods
                                                        .contains('card'))
                                                      const DropdownMenuItem(
                                                        value: 'card',
                                                        child: Text('Card'),
                                                      ),
                                                    if (allowedPaymentMethods
                                                        .contains('qr'))
                                                      const DropdownMenuItem(
                                                        value: 'qr',
                                                        child: Text('QR'),
                                                      ),
                                                  ],
                                                  onChanged: isSubmitting
                                                      ? null
                                                      : (method) {
                                                          if (method == null) {
                                                            return;
                                                          }
                                                          splitPayments[index]
                                                              .method = method;
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
                                                          splitPayments[index]
                                                              .dispose();
                                                          splitPayments
                                                              .removeAt(index);
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
                                            controller: splitPayments[index]
                                                .amountController,
                                            enabled: !isSubmitting,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            decoration: InputDecoration(
                                              labelText: 'Amount',
                                              prefixText: '\$ ',
                                              filled: true,
                                              fillColor: theme.colorScheme
                                                  .surfaceContainerLowest,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                            onChanged: (_) =>
                                                onTenderedChanged(),
                                          ),
                                          if (splitPayments[index].method ==
                                              'cash') ...[
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: splitPayments[index]
                                                  .tenderedController,
                                              enabled: !isSubmitting,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Cash received',
                                                prefixText: '\$ ',
                                                filled: true,
                                                fillColor: theme.colorScheme
                                                    .surfaceContainerLowest,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    12,
                                                  ),
                                                  borderSide: BorderSide.none,
                                                ),
                                              ),
                                              onChanged: (_) =>
                                                  onTenderedChanged(),
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
                                            _SplitPaymentLine(
                                                method: allowedPaymentMethods
                                                    .first),
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
                                  label: 'Allocated',
                                  value: currency.format(splitTotal),
                                ),
                                _SummaryRow(
                                  label: splitTotal > cart.total
                                      ? 'Overallocated'
                                      : 'Remaining',
                                  value: currency.format(
                                    splitTotal >= cart.total
                                        ? splitTotal - cart.total
                                        : cart.total - splitTotal,
                                  ),
                                ),
                                if (cashPortions.isNotEmpty)
                                  _SummaryRow(
                                    label: 'Cash change',
                                    value: splitCashChange == null
                                        ? '—'
                                        : currency.format(splitCashChange),
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
                            side: BorderSide(
                                color: theme.colorScheme.outlineVariant),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Amount received',
                                    helperText:
                                        'Enter cash received to calculate change.',
                                    helperMaxLines: 3,
                                    errorText: tenderedController.text
                                                .trim()
                                                .isNotEmpty &&
                                            (tenderedAmount == null ||
                                                !tenderedAmount!.isFinite)
                                        ? 'Enter a valid cash amount.'
                                        : change != null && change < 0
                                            ? 'Cash received is below the total.'
                                            : null,
                                    errorMaxLines: 3,
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
                                    for (final amount
                                        in cashQuickAmounts(cart.total))
                                      pos_ui.OutlinedButton(
                                        onPressed: isSubmitting
                                            ? null
                                            : () {
                                                tenderedController.text =
                                                    amount.toStringAsFixed(2);
                                                onTenderedChanged();
                                              },
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: Text(
                                          amount == cart.total
                                              ? 'Exact ${currency.format(amount)}'
                                              : currency.format(amount),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Riel cash · ${NumberFormat.decimalPattern('en').format(TillCurrency.rielPerDollar)}៛ = US\$1',
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final riel
                                        in TillCurrency.rielQuickAmounts(
                                            cart.total))
                                      pos_ui.OutlinedButton(
                                        onPressed: isSubmitting
                                            ? null
                                            : () {
                                                tenderedController.text =
                                                    TillCurrency.usdForRielNote(
                                                            riel)
                                                        .toStringAsFixed(2);
                                                onTenderedChanged();
                                              },
                                        child: Text(
                                          '${NumberFormat.decimalPattern('en').format(riel)}៛ / ${currency.format(TillCurrency.usdForRielNote(riel))}',
                                        ),
                                      ),
                                  ],
                                ),
                                if (change != null && change >= 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                      'Change equivalent: ${NumberFormat.decimalPattern('en').format(TillCurrency.rielForUsd(change))}៛'),
                                ],
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
                                  child: CheckoutAmountRow(
                                    label: change != null && change < 0
                                        ? 'Short by'
                                        : 'Change',
                                    value: change == null
                                        ? '—'
                                        : currency.format(change.abs()),
                                    emphasized: true,
                                    valueColor: change != null && change < 0
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      const Text(
                        'Complete Sale saves payment without printing a receipt. Cash payments open the drawer with either choice.',
                      ),
                    ],
                  ),
                ),
                CheckoutActions(
                  onSave: canSaveOrder ? onHold : null,
                  maxHeight: viewport.maxHeight * 0.5,
                  totalLabel: currency.format(cart.total),
                  secondaryTotalLabel:
                      '${NumberFormat.decimalPattern('en').format(TillCurrency.rielForUsd(cart.total))}៛',
                  enabled: canConfirm,
                  isSubmitting: isSubmitting,
                  onComplete: onConfirm,
                ),
              ],
            ),
          ),
        ),
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
    return CheckoutAmountRow(label: label, value: value);
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
  const _CheckoutSuccessView(
      {required this.confirmation, this.autoPrint = false});

  final OrderConfirmation confirmation;
  final bool autoPrint;

  @override
  ConsumerState<_CheckoutSuccessView> createState() =>
      _CheckoutSuccessViewState();
}

class _CheckoutSuccessViewState extends ConsumerState<_CheckoutSuccessView> {
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
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
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
                                subtitle: customer.phone == null ||
                                        customer.phone!.isEmpty
                                    ? null
                                    : Text(customer.phone!),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: theme.colorScheme.primary,
                                      )
                                    : null,
                                onTap: () =>
                                    Navigator.of(context).pop(customer),
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
