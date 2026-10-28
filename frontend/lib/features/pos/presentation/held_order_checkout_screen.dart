import 'package:flutter/material.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/receipt/customer_bill.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/receipt_action_buttons.dart';
import '../domain/pos_models.dart';
import 'widgets/cash_quick_amounts.dart';
import 'widgets/checkout_actions.dart';
import 'widgets/checkout_summary.dart';
import 'widgets/checkout_success_view.dart';

class HeldPaymentResult {
  const HeldPaymentResult({
    required this.method,
    this.tendered,
    this.splitPayments,
  });

  final String method;
  final double? tendered;
  final List<Map<String, dynamic>>? splitPayments;
}

class HeldOrderCheckoutScreen extends StatefulWidget {
  const HeldOrderCheckoutScreen({
    super.key,
    required this.total,
    required this.bill,
    required this.allowedMethods,
    required this.onPay,
  });

  final double total;
  final CustomerBill bill;
  final List<String> allowedMethods;
  final Future<OrderConfirmation> Function(HeldPaymentResult) onPay;

  @override
  State<HeldOrderCheckoutScreen> createState() =>
      _HeldOrderCheckoutScreenState();
}

class _HeldOrderCheckoutScreenState extends State<HeldOrderCheckoutScreen> {
  bool _submitting = false;
  bool _autoPrint = false;
  OrderConfirmation? _confirmation;
  String? _error;
  String _method = 'cash';
  final _scrollController = ScrollController();
  final _tenderedController = TextEditingController();
  final _firstAmount = TextEditingController();
  final _splitTendered = TextEditingController();
  late String _firstMethod;
  late String _secondMethod;

  @override
  void initState() {
    super.initState();
    _method = widget.allowedMethods.firstOrNull ?? '';
    _firstMethod = _method;
    _secondMethod =
        widget.allowedMethods.length > 1 ? widget.allowedMethods[1] : _method;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tenderedController.dispose();
    _firstAmount.dispose();
    _splitTendered.dispose();
    super.dispose();
  }

  double? get _tendered {
    final value = double.tryParse(_tenderedController.text.trim());
    return value;
  }

  double get _changeDue {
    final tendered = _tendered ?? 0;
    return tendered >= widget.total ? tendered - widget.total : 0;
  }

  bool get _canConfirm {
    if (_method == 'split') {
      final first = double.tryParse(_firstAmount.text);
      if (first == null || !first.isFinite) return false;
      final firstCents = (first * 100).round();
      final totalCents = (widget.total * 100).round();
      if (firstCents <= 0 || firstCents >= totalCents) return false;
      if (!widget.allowedMethods.contains(_firstMethod) ||
          !widget.allowedMethods.contains(_secondMethod)) {
        return false;
      }
      final cash = _firstMethod == 'cash'
          ? firstCents / 100
          : (_secondMethod == 'cash' ? (totalCents - firstCents) / 100 : 0.0);
      final tendered = double.tryParse(_splitTendered.text);
      return cash == 0 ||
          _splitTendered.text.trim().isEmpty ||
          (tendered != null && tendered.isFinite && tendered >= cash);
    }
    if (!widget.allowedMethods.contains(_method)) return false;
    if (_method != 'cash') {
      return true;
    }

    final tendered = _tendered;

    // An empty cash field means exact payment.
    if (_tenderedController.text.trim().isEmpty) {
      return true;
    }

    return tendered != null && tendered.isFinite && tendered >= widget.total;
  }

  String _formatMoney(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  Future<void> _confirm(bool printReceipt) async {
    if (_submitting || _confirmation != null || !_canConfirm) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final confirmation = await widget.onPay(HeldPaymentResult(
        method: _method,
        tendered: _method == 'cash' ? _tendered : null,
        splitPayments: _method == 'split' ? _splitPayload() : null,
      ));
      if (!mounted) return;
      setState(() {
        _confirmation = confirmation;
        _autoPrint = printReceipt;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiException
          ? error.message
          : 'Could not complete payment. Check the order before retrying.');
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<Map<String, dynamic>> _splitPayload() {
    final first = (double.parse(_firstAmount.text) * 100).round();
    final second = (widget.total * 100).round() - first;
    return [
      for (final portion in [(_firstMethod, first), (_secondMethod, second)])
        {
          'method': portion.$1,
          'amount': portion.$2 / 100,
          if (portion.$1 == 'cash')
            'tendered':
                double.tryParse(_splitTendered.text) ?? portion.$2 / 100,
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isCash = _method == 'cash';

    final confirmation = _confirmation;
    return PopScope(
      canPop: !_submitting && confirmation == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_submitting && confirmation != null) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: PageAppBar(
          title: Text(
              confirmation == null ? 'Review Order' : 'Payment Successful'),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _submitting
                ? null
                : () => Navigator.of(context).pop(confirmation != null),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: confirmation != null
            ? CheckoutSuccessView(
                confirmation: confirmation, autoPrint: _autoPrint)
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _submitting,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_error != null) ...[
                                    Semantics(
                                        liveRegion: true,
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                    const SizedBox(height: 16),
                                  ],
                                  _ReviewSection(
                                    title: widget.bill.tableName == null
                                        ? 'Order summary'
                                        : 'Order summary · ${widget.bill.tableName}',
                                    child: Column(
                                      children: [
                                        for (final item in widget.bill.items)
                                          CheckoutOrderLine(
                                            title: item.productName,
                                            variant: item.variantName,
                                            quantity: item.quantity,
                                            unitPrice:
                                                _formatMoney(item.unitPrice),
                                            lineTotal:
                                                _formatMoney(item.lineTotal),
                                          ),
                                        const Divider(),
                                        CheckoutAmountRow(
                                            label: 'Subtotal',
                                            value: _formatMoney(
                                                widget.bill.subtotal)),
                                        if (widget.bill.discountTotal != 0)
                                          CheckoutAmountRow(
                                              label: 'Discount',
                                              value: _formatMoney(
                                                  widget.bill.discountTotal)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text('Payment method',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 12),
                                  if (widget.allowedMethods.isEmpty)
                                    const Text(
                                        'No payment methods are enabled for this business.'),
                                  if (widget.allowedMethods.isNotEmpty)
                                    CheckoutChoiceSelector(
                                      choices: [
                                        for (final method
                                            in widget.allowedMethods)
                                          CheckoutChoice(
                                            method,
                                            method == 'qr'
                                                ? 'QR'
                                                : '${method[0].toUpperCase()}${method.substring(1)}',
                                            method == 'cash'
                                                ? Icons.payments_outlined
                                                : method == 'card'
                                                    ? Icons.credit_card
                                                    : Icons.qr_code_2,
                                          ),
                                        if (widget.allowedMethods.length > 1)
                                          const CheckoutChoice(
                                            'split',
                                            'Split',
                                            Icons.call_split_outlined,
                                          ),
                                      ],
                                      selected: _method,
                                      enabled: true,
                                      onChanged: (method) =>
                                          setState(() => _method = method),
                                    ),
                                  if (_method == 'split') ...[
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey('first-$_firstMethod'),
                                      initialValue: _firstMethod,
                                      decoration: const InputDecoration(
                                        labelText: 'First payment method',
                                      ),
                                      items: [
                                        for (final method
                                            in widget.allowedMethods)
                                          DropdownMenuItem(
                                            value: method,
                                            child: Text(method.toUpperCase()),
                                          ),
                                      ],
                                      onChanged: (value) => setState(() {
                                        _firstMethod = value!;
                                        if (_secondMethod == value) {
                                          _secondMethod =
                                              widget.allowedMethods.firstWhere(
                                            (m) => m != value,
                                          );
                                        }
                                      }),
                                    ),
                                    TextField(
                                      controller: _firstAmount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'First payment amount',
                                        prefixText: '\$ ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey('second-$_secondMethod'),
                                      initialValue: _secondMethod,
                                      decoration: const InputDecoration(
                                        labelText: 'Remaining payment method',
                                      ),
                                      items: [
                                        for (final method
                                            in widget.allowedMethods.where(
                                          (m) => m != _firstMethod,
                                        ))
                                          DropdownMenuItem(
                                            value: method,
                                            child: Text(method.toUpperCase()),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                          () => _secondMethod = value!),
                                    ),
                                    Text(
                                      'Remaining: ${_formatMoney(widget.total - (double.tryParse(_firstAmount.text) ?? 0))}',
                                    ),
                                    if (_firstMethod == 'cash' ||
                                        _secondMethod == 'cash')
                                      TextField(
                                        controller: _splitTendered,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Cash received for cash portion',
                                          hintText:
                                              'Leave blank for exact amount',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                  ],
                                  if (isCash) ...[
                                    const SizedBox(height: 24),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final amount
                                            in cashQuickAmounts(widget.total))
                                          OutlinedButton(
                                            onPressed: () => setState(
                                              () => _tenderedController.text =
                                                  amount.toStringAsFixed(2),
                                            ),
                                            child: Text(
                                              amount == widget.total
                                                  ? 'Exact'
                                                  : _formatMoney(amount),
                                            ),
                                          ),
                                      ],
                                    ),
                                    TextField(
                                      controller: _tenderedController,
                                      autofocus: false,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Cash received',
                                        prefixText: '\$ ',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: _canConfirm
                                            ? Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest
                                            : Theme.of(context)
                                                .colorScheme
                                                .errorContainer,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _canConfirm
                                                ? 'Change'
                                                : 'Remaining',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            _formatMoney(
                                              _tenderedController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? 0
                                                  : (_canConfirm
                                                      ? _changeDue
                                                      : widget.total -
                                                          (_tendered ?? 0)),
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: _canConfirm
                                                      ? null
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  _ReviewSection(
                                    title: 'Customer bill',
                                    child: BillActionButtons(bill: widget.bill),
                                  ),
                                  const SizedBox(height: 20),
                                  CheckoutActions(
                                    inline: true,
                                    totalLabel: _formatMoney(widget.total),
                                    enabled: _canConfirm,
                                    isSubmitting: _submitting,
                                    onComplete: _confirm,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}
