import '../../../core/theme/coffee_studio_theme.dart';
import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../auth/presentation/manager_pin_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/receipt/customer_bill.dart';
import '../../../core/receipt/last_receipt_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
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
import 'held_order_checkout_screen.dart';

class _EditableOrderLine {
  const _EditableOrderLine({
    required this.productId,
    this.productVariantId,
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.unitPrice,
    this.orderItemId,
    this.modifierIds = const [],
    this.comboSelections = const [],
  });

  final List<int> modifierIds, comboSelections;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantName;
  final int quantity;
  final double unitPrice;
  final int? orderItemId;

  double get lineTotal => unitPrice * quantity;

  String get lineKey =>
      '$productId:${productVariantId ?? 'base'}:${(modifierIds.toList()..sort()).join(',')}:${comboSelections.join(',')}';

  _EditableOrderLine copyWith({int? quantity}) {
    return _EditableOrderLine(
      productId: productId,
      productVariantId: productVariantId,
      productName: productName,
      variantName: variantName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice,
      orderItemId: orderItemId,
      modifierIds: modifierIds,
      comboSelections: comboSelections,
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
      modifierIds: List<int>.from(
        item.menuConfiguration['modifier_ids'] as List? ?? [],
      ),
      comboSelections: [
        for (final c in item.menuConfiguration['components'] as List? ?? [])
          c['product_id'] as int,
      ],
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
      appBar: PageAppBar(title: Text(appBarTitle)),
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
  bool _allowLeave = false;

  bool get _hasChanges {
    final original = _editableLinesFromOrder(_order);
    if (original.length != _lines.length) return true;
    return original.any(
      (line) => !_lines.any(
        (edited) =>
            edited.lineKey == line.lineKey && edited.quantity == line.quantity,
      ),
    );
  }

  Future<void> _requestLeave() async {
    if (_isBusy || _allowLeave) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save changes before leaving?'),
        content: const Text('This table has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Discard Changes'),
          ),
          FilledButton(
            onPressed: _lines.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _saveOrder();
    }
    if (choice == 'discard') {
      setState(() => _allowLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  // Merge duplicate product/variant rows into one editable bill line.
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

  void _addConfigured(CartItem item) =>
      _addProduct(item.product, variant: item.variant, configured: item);

  void _addProduct(
    PosProduct product, {
    PosProductVariant? variant,
    CartItem? configured,
  }) {
    final newLine = configured == null
        ? _EditableOrderLine.fromProduct(product, variant: variant)
        : _EditableOrderLine(
            productId: product.id,
            productVariantId: variant?.id,
            productName: product.name,
            variantName: [
              if (variant != null) variant.name,
              configured.configurationLabel,
            ].where((s) => s.isNotEmpty).join(' · '),
            quantity: 1,
            unitPrice: configured.unitPrice,
            modifierIds: configured.modifierIds,
            comboSelections: configured.comboSelections,
          );

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

  Future<void> _changeQuantity(String lineKey, int delta) async {
    final index = _lines.indexWhere((line) => line.lineKey == lineKey);
    if (index == -1) return;

    final line = _lines[index];
    final newQuantity = line.quantity + delta;
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

  Future<void> _removeLine(String lineKey) async {
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

    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<OrderDetail> _saveCurrentOrder() async {
    final items = _lines
        .map(
          (line) => <String, dynamic>{
            if (line.modifierIds.isNotEmpty) 'modifier_ids': line.modifierIds,
            if (line.comboSelections.isNotEmpty)
              'combo_selections': line.comboSelections,
            'product_id': line.productId,
            'product_variant_id': line.productVariantId,
            'quantity': line.quantity,
          },
        )
        .toList();

    final repository = ref.read(posRepositoryProvider);
    await repository.updateHeldOrder(
      expectedRevision: _order.editRevision,
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
      setState(() {
        _isBusy = false;
        _allowLeave = true;
      });
      context.pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not save order. Check its status before retrying.',
          ),
          action: SnackBarAction(label: 'Reload', onPressed: _reloadOrder),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _reloadOrder() async {
    final reload = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reload latest order?'),
        content: const Text(
          'Your unsaved edits will be replaced with the saved order. Review it before making changes again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (reload == true && mounted) {
      ref.read(orderDetailControllerProvider(_order.id).notifier).refresh();
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
      final pin = await requestManagerPin(
        context,
        ref,
        action: 'Approve order cancellation',
      );
      if (pin == null || !mounted) return;
      final repo = ref.read(posRepositoryProvider);
      if (pin.isEmpty) {
        await repo.cancelHeldOrder(orderId: _order.id);
      } else {
        await repo.cancelHeldOrder(
          orderId: _order.id,
          managerPin: pin,
          branchId: ref.read(currentBranchProvider)?.id,
        );
      }
      if (!mounted) return;
      ref.read(ordersListControllerProvider.notifier).refresh();
      setState(() => _isBusy = false);
      context.go('/pos/select-table');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not cancel order. Refresh its status before trying again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _payOrder() async {
    if (_isBusy || _lines.isEmpty) return;
    setState(() => _isBusy = true);

    try {
      // Save the authoritative held order before collecting payment.
      final saved = await _saveCurrentOrder();
      if (!mounted) return;

      final customerBill = CustomerBill.fromOrderDetail(saved);
      final auth = ref.read(authControllerProvider);
      final methods = auth is AuthAuthenticated
          ? auth.user.allowedPaymentMethods
          : const ['cash'];
      setState(() => _isShowingPayment = true);
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => HeldOrderCheckoutScreen(
            total: saved.total,
            bill: customerBill,
            allowedMethods: methods,
            onPay: (result) async {
              final confirmation =
                  await ref.read(posRepositoryProvider).payHeldOrder(
                        orderId: saved.id,
                        paymentMethod: result.method,
                        tendered: result.tendered,
                        splitPayments: result.splitPayments,
                        expectedTotal: saved.total,
                        branchId: saved.branch?.id,
                      );
              if (mounted) {
                ref.invalidate(lastCompletedOrderProvider);
                ref.read(ordersListControllerProvider.notifier).refresh();
              }
              return confirmation;
            },
          ),
        ),
      );
      if (!mounted || completed != true) return;

      ref.read(ordersListControllerProvider.notifier).refresh();
      context.go('/pos/select-table');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not save order. Payment was not started.',
          ),
          action: SnackBarAction(label: 'Reload', onPressed: _reloadOrder),
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

  /// A phone keeps the product grid usable, with the full editor in a sheet.
  Future<void> _showOrderSummary() async {
    final currency = NumberFormat.currency(symbol: r'$');
    final auth = ref.read(authControllerProvider);
    final canCancel =
        auth is AuthAuthenticated && auth.user.hasPermission('orders.cancel');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: _OrderPanel(
            order: _order,
            lines: _lines,
            subtotal: _subtotal,
            discount: _discount,
            total: _total,
            currency: currency,
            onSave: () {
              Navigator.of(sheetContext).pop();
              _saveOrder();
            },
            onPay: () {
              Navigator.of(sheetContext).pop();
              _payOrder();
            },
            onDiscard: () {
              Navigator.of(sheetContext).pop();
              _discardChanges();
            },
            onCancel: canCancel
                ? () {
                    Navigator.of(sheetContext).pop();
                    _cancelOrder();
                  }
                : null,
            onIncrement: (key) async {
              await _changeQuantity(key, 1);
              if (sheetContext.mounted) updateSheet(() {});
            },
            onDecrement: (key) async {
              await _changeQuantity(key, -1);
              if (sheetContext.mounted) updateSheet(() {});
            },
            onRemove: (key) async {
              await _removeLine(key);
              if (sheetContext.mounted) updateSheet(() {});
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$');
    final catalogState = ref.watch(posCatalogControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final canCancel = authState is AuthAuthenticated &&
        authState.user.hasPermission('orders.cancel');

    return PopScope(
      canPop: !_isBusy && (_allowLeave || !_hasChanges),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isBusy && _hasChanges) _requestLeave();
      },
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
                  onConfiguredSelected: _addConfigured,
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: productPanel),
                      const VerticalDivider(width: 1),
                      SizedBox(
                          width: MediaQuery.sizeOf(context).width >= 1200
                              ? 380
                              : 340,
                          child: Material(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant)),
                              clipBehavior: Clip.antiAlias,
                              child: orderPanel)),
                    ],
                  );
                }

                final itemCount = _lines.fold<int>(
                  0,
                  (count, line) => count + line.quantity,
                );
                return Column(
                  children: [
                    Expanded(child: productPanel),
                    const Divider(height: 1),
                    SafeArea(
                      top: false,
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Order Summary · $itemCount items',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    currency.format(_total),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: pos_ui.OutlinedButton(
                                      onPressed: _showOrderSummary,
                                      child: const Text('View / Edit'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: pos_ui.PosActionButton(
                                      onPressed:
                                          _lines.isEmpty ? null : _payOrder,
                                      child: const Text('Review & Pay'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: pos_ui.SecondaryButton(
                                  onPressed: _lines.isEmpty ? null : _saveOrder,
                                  child: Text(
                                    _hasChanges ? 'Save Changes' : 'Save Order',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
    // Totals and actions belong to the scrollable content. On a short device,
    // a fixed footer exceeded the available height by more than 100 pixels.
    return Column(
      children: [
        _OrderHeader(order: order),
        const Divider(height: 1),
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('open-order-summary-scroll'),
            slivers: [
              if (lines.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No items in this order.')))),
              SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                final line = lines[index];
                if (CoffeeStudioTheme.active(context)) {
                  final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.productName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (line.variantName != null)
                          Text(line.variantName!,
                              style: Theme.of(context).textTheme.bodySmall),
                        Text('${currency.format(line.unitPrice)} each',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]);
                  final qty = Container(
                      decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        pos_ui.IconButton(
                            tooltip: 'Decrease quantity',
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: () => onDecrement(line.lineKey)),
                        Text('${line.quantity}'),
                        pos_ui.IconButton(
                            tooltip: 'Increase quantity',
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: () => onIncrement(line.lineKey)),
                      ]));
                  final end = Column(mainAxisSize: MainAxisSize.min, children: [
                    pos_ui.IconButton(
                        tooltip: 'Remove item',
                        icon: Icon(Icons.delete_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () => onRemove(line.lineKey)),
                    Text(currency.format(line.lineTotal),
                        style: Theme.of(context).textTheme.titleSmall),
                  ]);
                  return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(14)),
                      child: LayoutBuilder(builder: (context, box) {
                        if (box.maxWidth < 310 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                details,
                                const SizedBox(height: 10),
                                Row(children: [qty, const Spacer(), end])
                              ]);
                        }
                        return Row(children: [
                          Expanded(child: details),
                          const SizedBox(width: 10),
                          qty,
                          const SizedBox(width: 10),
                          end
                        ]);
                      }));
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                            color: Theme.of(context).colorScheme.outlineVariant,
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
                                    ?.copyWith(fontWeight: FontWeight.w700),
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
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                );
              }, childCount: lines.length)),
              SliverLayoutBuilder(
                  builder: (context, sliver) => SliverToBoxAdapter(
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: (sliver.viewportMainAxisExtent -
                                      sliver.precedingScrollExtent)
                                  .clamp(0.0, double.infinity)),
                          child: Align(
                              alignment: Alignment.bottomCenter,
                              child: _OrderTotals(
                                subtotal: subtotal,
                                discount: discount,
                                total: total,
                                currency: currency,
                                onSave: onSave,
                                onDiscard: onDiscard,
                                onCancel: onCancel,
                                onPay: onPay,
                              ))))),
            ],
          ),
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
    required this.onConfiguredSelected,
  });

  final void Function(CartItem item) onConfiguredSelected;
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
        CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 8),
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
                ],
              ),
            ),
            if (visibleProducts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No products found.')),
              )
            else
              ProductGrid(
                products: visibleProducts,
                crossAxisCount: crossAxisCount,
                sliver: true,
                onProductSelected: onProductSelected,
                onVariantSelected: onVariantSelected,
                onConfiguredSelected: onConfiguredSelected,
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
    if (CoffeeStudioTheme.active(context)) {
      return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant))),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Order details & actions',
                        style: TextStyle(fontSize: 13)),
                    children: [
                      _TotalRow(
                          label: 'Subtotal', value: currency.format(subtotal)),
                      if (discount > 0)
                        _TotalRow(
                            label: 'Discount',
                            value: '-${currency.format(discount)}'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        pos_ui.OutlinedButton(
                            onPressed: onSave, child: const Text('Save')),
                        pos_ui.DangerButton.outlined(
                            onPressed: onDiscard, child: const Text('Discard')),
                        if (onCancel != null)
                          pos_ui.DangerButton.outlined(
                              onPressed: onCancel,
                              child: const Text('Cancel Order')),
                      ]),
                    ]),
                const SizedBox(height: 6),
                _TotalRow(
                    label: 'Total',
                    value: currency.format(total),
                    emphasized: true),
                const SizedBox(height: 8),
                pos_ui.PosActionButton(
                    onPressed: onPay, child: const Text('Review & Pay')),
              ]));
    }
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
        ? Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
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
