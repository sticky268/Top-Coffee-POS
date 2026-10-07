import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/receipt/customer_bill.dart';
import '../../../core/receipt/last_receipt_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../core/widgets/receipt_action_buttons.dart';
import '../../orders/application/order_detail_controller.dart';
import '../../orders/application/orders_list_controller.dart';
import '../../orders/application/order_detail_state.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/domain/order_models.dart';
import '../application/pos_catalog_controller.dart';
import '../application/pos_catalog_state.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';
import 'widgets/category_selector.dart';
import 'widgets/product_grid.dart';
import 'widgets/product_search_field.dart';

class _EditableOrderLine {
  const _EditableOrderLine({
    required this.productId,
    this.productVariantId,
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.unitPrice,
    this.orderItemId,
  });

  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantName;
  final int quantity;
  final double unitPrice;
  final int? orderItemId;

  double get lineTotal => unitPrice * quantity;

  String get lineKey => '$productId:${productVariantId ?? 'base'}';

  _EditableOrderLine copyWith({int? quantity}) {
    return _EditableOrderLine(
      productId: productId,
      productVariantId: productVariantId,
      productName: productName,
      variantName: variantName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice,
      orderItemId: orderItemId,
    );
  }

  factory _EditableOrderLine.fromOrderItem(OrderLineItem item) {
    return _EditableOrderLine(
      productId: item.productId,
      productVariantId: item.productVariantId,
      productName: item.productName,
      variantName: item.variantName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      orderItemId: item.id,
    );
  }

  factory _EditableOrderLine.fromProduct(
    PosProduct product, {
    PosProductVariant? variant,
  }) {
    return _EditableOrderLine(
      productId: product.id,
      productVariantId: variant?.id,
      productName: product.name,
      variantName: variant?.name,
      quantity: 1,
      unitPrice: variant?.price ?? product.price,
    );
  }
}

class OpenOrderScreen extends ConsumerWidget {
  const OpenOrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailControllerProvider(orderId));

    final appBarTitle = state is OrderDetailLoaded
        ? 'Open Order ${state.order.displayOrderReference}'
        : 'Open Order';

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: switch (state) {
        OrderDetailLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        OrderDetailError(:final message) => _ErrorView(
          message: message,
          onRetry: () => ref
              .read(orderDetailControllerProvider(orderId).notifier)
              .refresh(),
        ),
        OrderDetailLoaded(:final order) => _OpenOrderContent(order: order),
      },
    );
  }
}

class _OpenOrderContent extends ConsumerStatefulWidget {
  const _OpenOrderContent({required this.order});

  final OrderDetail order;

  @override
  ConsumerState<_OpenOrderContent> createState() => _OpenOrderContentState();
}

class _OpenOrderContentState extends ConsumerState<_OpenOrderContent> {
  late List<_EditableOrderLine> _lines;
  late OrderDetail _order;
  bool _isBusy = false;
  bool _isShowingPayment = false;

  // A bill can contain multiple kitchen batches for the same product.
  // Combine those rows for the cashier while retaining the submitted floor.
  List<_EditableOrderLine> _editableLinesFromOrder(OrderDetail order) {
    final merged = <String, _EditableOrderLine>{};
    for (final item in order.items) {
      final line = _EditableOrderLine.fromOrderItem(item);
      final previous = merged[line.lineKey];
      if (previous == null) {
        merged[line.lineKey] = line;
      } else {
        final quantity = previous.quantity + line.quantity;
        merged[line.lineKey] = _EditableOrderLine(
          productId: line.productId,
          productVariantId: line.productVariantId,
          productName: line.productName,
          variantName: line.variantName,
          quantity: quantity,
          unitPrice: (previous.lineTotal + line.lineTotal) / quantity,
        );
      }
    }
    return merged.values.toList();
  }

  int _submittedQuantity(String lineKey) {
    return _editableLinesFromOrder(_order)
        .where((line) => line.lineKey == lineKey)
        .fold(0, (sum, line) => sum + line.quantity);
  }

  void _showSubmittedItemWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Items sent to the kitchen cannot be reduced or removed.'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _lines = _editableLinesFromOrder(_order);
  }

  double get _subtotal => _lines.fold(0.0, (sum, line) => sum + line.lineTotal);

  double get _discount => _order.discountTotal;

  double get _total {
    final result = _subtotal - _discount;
    return result < 0 ? 0 : result;
  }

  void _addProduct(PosProduct product, {PosProductVariant? variant}) {
    final newLine = _EditableOrderLine.fromProduct(product, variant: variant);

    final existingIndex = _lines.indexWhere(
      (line) => line.lineKey == newLine.lineKey,
    );

    setState(() {
      if (existingIndex == -1) {
        _lines = [..._lines, newLine];
      } else {
        final updated = [..._lines];
        final existing = updated[existingIndex];
        updated[existingIndex] = existing.copyWith(
          quantity: existing.quantity + 1,
        );
        _lines = updated;
      }
    });
  }

  void _updateCatalogSearch(String query) {
    ref.read(posCatalogControllerProvider.notifier).updateSearchQuery(query);
  }

  void _updateCatalogCategory(int? categoryId) {
    ref.read(posCatalogControllerProvider.notifier).selectCategory(categoryId);
  }

  void _addProductVariant(PosProduct product, PosProductVariant variant) {
    _addProduct(product, variant: variant);
  }

  void _changeQuantity(String lineKey, int delta) {
    final index = _lines.indexWhere((line) => line.lineKey == lineKey);
    if (index == -1) return;

    final line = _lines[index];
    final newQuantity = line.quantity + delta;
    if (newQuantity < _submittedQuantity(lineKey)) {
      _showSubmittedItemWarning();
      return;
    }

    setState(() {
      if (newQuantity <= 0) {
        _lines = [
          for (final item in _lines)
            if (item.lineKey != lineKey) item,
        ];
      } else {
        final updated = [..._lines];
        updated[index] = line.copyWith(quantity: newQuantity);
        _lines = updated;
      }
    });
  }

  void _removeLine(String lineKey) {
    if (_submittedQuantity(lineKey) > 0) {
      _showSubmittedItemWarning();
      return;
    }
    setState(() {
      _lines = [
        for (final item in _lines)
          if (item.lineKey != lineKey) item,
      ];
    });
  }

  Future<void> _discardChanges() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Any changes made to this order will be lost.'),
        actions: [
          pos_ui.SecondaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Editing'),
          ),
          pos_ui.DangerButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard Changes'),
          ),
        ],
      ),
    );

    if (shouldDiscard != true || !mounted) return;

    context.pushReplacement('/pos/select-table');
  }

  Future<OrderDetail> _saveCurrentOrder() async {
    final items = _lines
        .map(
          (line) => <String, dynamic>{
            'product_id': line.productId,
            'product_variant_id': line.productVariantId,
            'quantity': line.quantity,
          },
        )
        .toList();

    await ref
        .read(posRepositoryProvider)
        .updateHeldOrder(
          orderId: _order.id,
          items: items,
          discountTotal: _discount,
          branchId: _order.branch?.id,
        );

    final saved = await ref.read(ordersRepositoryProvider).getOrder(_order.id);
    if (saved.status != 'held') {
      throw StateError('This order is no longer open. Reload its details.');
    }
    if (mounted) {
      setState(() {
        _order = saved;
        _lines = _editableLinesFromOrder(saved);
      });
    }
    return saved;
  }

  Future<void> _saveOrder() async {
    if (_isBusy || _lines.isEmpty) return;
    setState(() => _isBusy = true);

    try {
      await _saveCurrentOrder();
      if (!mounted) return;
      // Do not refresh the watched detail provider here: its loading state
      // disposes this editor before navigation can complete. The detail
      // screen refreshes itself when this route returns.
      await ref.read(ordersListControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order saved successfully.')),
      );
      // PopScope blocks navigation while _isBusy is true.
      setState(() => _isBusy = false);
      context.pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save order: $error')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cancelOrder() async {
    if (_isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
          'This will cancel the entire held order and release its table. '
          'The order remains in history and cannot be reopened.',
        ),
        actions: [
          pos_ui.SecondaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Order'),
          ),
          pos_ui.DangerButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await ref.read(posRepositoryProvider).cancelHeldOrder(orderId: _order.id);
      if (!mounted) return;
      ref.read(ordersListControllerProvider.notifier).refresh();
      setState(() => _isBusy = false);
      context.go('/pos/select-table');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel order: $error')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _payOrder() async {
    if (_isBusy || _lines.isEmpty) return;
    setState(() => _isBusy = true);
    var isPaying = false;

    try {
      // Save the authoritative held order before collecting payment.
      final saved = await _saveCurrentOrder();
      if (!mounted) return;

      final customerBill = CustomerBill.fromOrderDetail(saved);
      setState(() => _isShowingPayment = true);
      final result = await showDialog<_PaymentResult>(
        context: context,
        builder: (_) => _PaymentDialog(
          total: saved.total,
          bill: customerBill,
        ),
      );
      if (!mounted) return;
      setState(() => _isShowingPayment = false);
      if (result == null) return;

      isPaying = true;
      await ref
          .read(posRepositoryProvider)
          .payHeldOrder(
            orderId: saved.id,
            paymentMethod: result.method,
            tendered: result.tendered,
            expectedTotal: saved.total,
            branchId: saved.branch?.id,
          );
      if (!mounted) return;

      // Payment is authoritative at this point. Show success immediately;
      // refreshing list/cache data should not delay cashier feedback.
      ref.invalidate(lastCompletedOrderProvider);
      setState(() => _isBusy = false);

      await showPaymentReceiptDialog(
        context: context,
        orderId: saved.id,
        orderReference: saved.displayOrderReference,
      );
      if (!mounted) return;

      ref.read(ordersListControllerProvider.notifier).refresh();
      context.go('/pos/select-table');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPaying
                ? 'Could not complete payment: $error'
                : 'Could not save order. Payment was not started: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isShowingPayment = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$');
    final catalogState = ref.watch(posCatalogControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final canCancel = authState is AuthAuthenticated &&
        authState.user.hasPermission('orders.cancel');

    return PopScope(
      canPop: !_isBusy,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isBusy,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                final productColumns = constraints.maxWidth >= 1024
                    ? 4
                    : (constraints.maxWidth >= 600 ? 3 : 2);

                final orderPanel = _OrderPanel(
                  order: _order,
                  lines: _lines,
                  subtotal: _subtotal,
                  discount: _discount,
                  total: _total,
                  currency: currency,
                  onSave: _saveOrder,
                  onPay: _payOrder,
                  onDiscard: _discardChanges,
                  onCancel: canCancel ? _cancelOrder : null,
                  onIncrement: (lineKey) => _changeQuantity(lineKey, 1),
                  onDecrement: (lineKey) => _changeQuantity(lineKey, -1),
                  onRemove: _removeLine,
                );

                final productPanel = _ProductCatalogPanel(
                  state: catalogState,
                  crossAxisCount: productColumns,
                  onProductSelected: _addProduct,
                  onVariantSelected: _addProductVariant,
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: productPanel),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 340, child: orderPanel),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(flex: 3, child: productPanel),
                    const Divider(height: 1),
                    Expanded(flex: 2, child: orderPanel),
                  ],
                );
              },
            ),
          ),
          if (_isBusy && !_isShowingPayment)
            const Positioned.fill(
              child: ColoredBox(
                color: AppColors.scrim,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentResult {
  const _PaymentResult({required this.method, this.tendered});

  final String method;
  final double? tendered;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total, required this.bill});

  final double total;
  final CustomerBill bill;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _method = 'cash';
  final _tenderedController = TextEditingController();

  @override
  void dispose() {
    _tenderedController.dispose();
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
    if (_method != 'cash') {
      return true;
    }

    final tendered = _tendered;

    // An empty cash field means exact payment.
    if (_tenderedController.text.trim().isEmpty) {
      return true;
    }

    return tendered != null && tendered >= widget.total;
  }

  String _formatMoney(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  void _confirm() {
    if (!_canConfirm) return;

    Navigator.of(context).pop(
      _PaymentResult(
        method: _method,
        tendered: _method == 'cash' ? _tendered : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCash = _method == 'cash';

    return AlertDialog(
      title: const Text('Review Bill & Pay'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Review or give the customer the unpaid bill before collecting payment.',
            ),
            const SizedBox(height: 16),
            BillActionButtons(
              bill: widget.bill,
              showHeading: true,
            ),
            const SizedBox(height: 24),
            Text('Total', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              _formatMoney(widget.total),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'cash',
                  label: Text('Cash'),
                  icon: Icon(Icons.payments_outlined),
                ),
                ButtonSegment<String>(
                  value: 'card',
                  label: Text('Card'),
                  icon: Icon(Icons.credit_card),
                ),
                ButtonSegment<String>(
                  value: 'qr',
                  label: Text('QR'),
                  icon: Icon(Icons.qr_code_2),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (selection) {
                setState(() {
                  _method = selection.first;
                });
              },
            ),
            if (isCash) ...[
              const SizedBox(height: 24),
              TextField(
                controller: _tenderedController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
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
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.errorContainer,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _canConfirm ? 'Change' : 'Remaining',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _formatMoney(
                        _tenderedController.text.trim().isEmpty
                            ? 0
                            : (_canConfirm
                                  ? _changeDue
                                  : widget.total - (_tendered ?? 0)),
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _canConfirm
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          ),
        ),
      ),
      actions: [
        pos_ui.SecondaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        pos_ui.PosActionButton(
          onPressed: _canConfirm ? _confirm : null,
          child: const Text('Confirm Payment'),
        ),
      ],
    );
  }
}

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.order,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.currency,
    required this.onSave,
    required this.onPay,
    required this.onDiscard,
    required this.onCancel,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final OrderDetail order;
  final List<_EditableOrderLine> lines;
  final double subtotal;
  final double discount;
  final double total;
  final NumberFormat currency;
  final VoidCallback onSave;
  final VoidCallback onPay;
  final VoidCallback onDiscard;
  final VoidCallback? onCancel;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OrderHeader(order: order),
        const Divider(height: 1),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('No items in this order.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final line = lines[index];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.productName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (line.variantName != null) ...[
                                    const SizedBox(height: 3),
                                    Text(line.variantName!),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    currency.format(line.unitPrice),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            pos_ui.IconButton(
                              tooltip: 'Remove item',
                              onPressed: () => onRemove(line.lineKey),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  pos_ui.IconButton(
                                    tooltip: 'Decrease quantity',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => onDecrement(line.lineKey),
                                    icon: const Icon(Icons.remove),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${line.quantity}',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  pos_ui.IconButton(
                                    tooltip: 'Increase quantity',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => onIncrement(line.lineKey),
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 78,
                              child: Text(
                                currency.format(line.lineTotal),
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                    );
                  },
                ),
        ),
        _OrderTotals(
          subtotal: subtotal,
          discount: discount,
          total: total,
          currency: currency,
          onSave: onSave,
          onDiscard: onDiscard,
          onCancel: onCancel,
          onPay: onPay,
        ),
      ],
    );
  }
}

class _ProductCatalogPanel extends StatelessWidget {
  const _ProductCatalogPanel({
    required this.state,
    required this.crossAxisCount,
    required this.onProductSelected,
    required this.onVariantSelected,
  });

  final PosCatalogState state;
  final int crossAxisCount;
  final void Function(PosProduct product) onProductSelected;
  final void Function(PosProduct product, PosProductVariant variant)
  onVariantSelected;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PosCatalogLoading() => const Center(child: CircularProgressIndicator()),
      PosCatalogError(:final message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
      PosCatalogLoaded(
        :final categories,
        :final visibleProducts,
        :final selectedCategoryId,
      ) =>
        Column(
              children: [
                const SizedBox(height: 16),
                ProductSearchField(
                    onChanged: (query) => context
                        .findAncestorStateOfType<_OpenOrderContentState>()
                        ?._updateCatalogSearch(query),
                  ),
                const SizedBox(height: 8),
                CategorySelector(
                  categories: categories,
                  selectedCategoryId: selectedCategoryId,
                  onSelected: (id) => context
                      .findAncestorStateOfType<_OpenOrderContentState>()
                      ?._updateCatalogCategory(id),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: visibleProducts.isEmpty
                      ? const Center(child: Text('No products found.'))
                      : ProductGrid(
                          products: visibleProducts,
                          crossAxisCount: crossAxisCount,
                          onProductSelected: onProductSelected,
                          onVariantSelected: onVariantSelected,
                        ),
                ),
              ],
            ),
    };
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order Summary',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (order.table != null)
                Chip(
                  avatar: const Icon(Icons.table_restaurant, size: 16),
                  label: Text(order.table!.name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.displayOrderReference,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTotals extends StatelessWidget {
  const _OrderTotals({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.currency,
    required this.onSave,
    required this.onDiscard,
    required this.onCancel,
    required this.onPay,
  });

  final double subtotal;
  final double discount;
  final double total;
  final NumberFormat currency;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback? onCancel;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          _TotalRow(label: 'Subtotal', value: currency.format(subtotal)),
          if (discount > 0)
            _TotalRow(
              label: 'Discount',
              value: '-${currency.format(discount)}',
            ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'Total',
            value: currency.format(total),
            emphasized: true,
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: pos_ui.DangerButton.outlined(
                onPressed: onCancel,
                child: const Text('Cancel Order'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: pos_ui.DangerButton.outlined(
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: pos_ui.OutlinedButton(
                  onPressed: onSave,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: pos_ui.PosActionButton(
              onPressed: onPay,
              child: const Text('Review & Pay'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 16),
          pos_ui.OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
