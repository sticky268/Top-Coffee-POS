import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../pos/application/pos_catalog_controller.dart';
import '../../pos/application/pos_catalog_state.dart';
import '../../pos/domain/pos_models.dart';
import '../../pos/presentation/widgets/category_selector.dart';
import '../../pos/presentation/widgets/product_grid.dart';
import '../../pos/presentation/widgets/product_search_field.dart';
import '../application/edit_order_controller.dart';
import '../application/edit_order_state.dart';
import '../application/order_detail_controller.dart';
import '../application/order_detail_state.dart';
import '../domain/order_models.dart';

class EditOrderScreen extends ConsumerWidget {
  const EditOrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(orderDetailControllerProvider(orderId));

    final title = orderState is OrderDetailLoaded
        ? 'Adjust ${orderState.order.displayOrderReference}'
        : 'Adjust Completed Order';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: switch (orderState) {
        OrderDetailLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        OrderDetailError(:final message) => _ErrorView(
          message: message,
          onRetry: () => ref
              .read(orderDetailControllerProvider(orderId).notifier)
              .refresh(),
        ),
        OrderDetailLoaded(:final order) => _EditOrderBody(order: order),
      },
    );
  }
}

class _EditOrderBody extends ConsumerWidget {
  const _EditOrderBody({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(posCatalogControllerProvider);

    return switch (catalogState) {
      PosCatalogLoading() => const Center(child: CircularProgressIndicator()),
      PosCatalogError(:final message) => _ErrorView(
        message: message,
        onRetry: () =>
            ref.read(posCatalogControllerProvider.notifier).refresh(),
      ),
      PosCatalogLoaded(
        :final categories,
        :final selectedCategoryId,
        :final visibleProducts,
      ) =>
        _LoadedEditOrderBody(
          order: order,
          categories: categories,
          selectedCategoryId: selectedCategoryId,
          products: visibleProducts,
        ),
    };
  }
}

class _LoadedEditOrderBody extends ConsumerWidget {
  const _LoadedEditOrderBody({
    required this.order,
    required this.categories,
    required this.selectedCategoryId,
    required this.products,
  });

  final OrderDetail order;
  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editState = ref.watch(editOrderControllerProvider(order));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final productColumns = constraints.maxWidth >= 1024
            ? 4
            : (constraints.maxWidth >= 600 ? 3 : 2);

        if (isCompact) {
          return Column(
            children: [
              Expanded(
                flex: 3,
                child: _CatalogSection(
                  order: order,
                  categories: categories,
                  selectedCategoryId: selectedCategoryId,
                  products: products,
                  crossAxisCount: productColumns,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                flex: 2,
                child: _EditCartPanel(order: order, state: editState),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: _CatalogSection(
                order: order,
                categories: categories,
                selectedCategoryId: selectedCategoryId,
                products: products,
                crossAxisCount: productColumns,
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: _EditCartPanel(order: order, state: editState),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogSection extends ConsumerWidget {
  const _CatalogSection({
    required this.order,
    required this.categories,
    required this.selectedCategoryId,
    required this.products,
    required this.crossAxisCount,
  });

  final OrderDetail order;
  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editOrderControllerProvider(order).notifier);

    return Column(
      children: [
        const SizedBox(height: 16),
        ProductSearchField(
          onChanged: (query) => ref
              .read(posCatalogControllerProvider.notifier)
              .updateSearchQuery(query),
        ),
        const SizedBox(height: 8),
        CategorySelector(
          categories: categories,
          selectedCategoryId: selectedCategoryId,
          onSelected: (id) => ref
              .read(posCatalogControllerProvider.notifier)
              .selectCategory(id),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ProductGrid(
            products: products,
            crossAxisCount: crossAxisCount,
            onProductSelected: (product) => controller.addItem(product),
            onVariantSelected: (product, variant) =>
                controller.addItem(product, variant: variant),
          ),
        ),
      ],
    );
  }
}

class _EditCartPanel extends ConsumerWidget {
  const _EditCartPanel({required this.order, required this.state});

  final OrderDetail order;
  final EditOrderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editOrderControllerProvider(order).notifier);
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Edited Order', style: theme.textTheme.titleMedium),
              ),
              if (!state.isEmpty)
                pos_ui.DangerButton.outlinedIcon(
                  onPressed: state.isSaving
                      ? null
                      : () => _confirmClear(context, controller),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ),
        Expanded(
          child: state.isEmpty
              ? const Center(
                  child: Text('Order must contain at least one item'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _EditCartLine(
                      order: order,
                      item: state.items[index],
                      enabled: !state.isSaving,
                    );
                  },
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
                value: currency.format(state.subtotal),
              ),
              _DiscountEditor(
                value: state.discountTotal,
                enabled: !state.isSaving,
                onChanged: controller.setDiscount,
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  Text(
                    currency.format(state.total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: pos_ui.OutlinedButton(
                      onPressed: state.isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: pos_ui.PrimaryButton(
                      onPressed: state.isSaving || state.isEmpty
                          ? null
                          : () => _save(context, ref, order),
                      child: state.isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    EditOrderController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear edited order?'),
        content: const Text('This removes all items from the edited order.'),
        actions: [
          pos_ui.SecondaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          pos_ui.PrimaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      controller.clear();
    }
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
  ) async {
    final controller = ref.read(editOrderControllerProvider(order).notifier);

    final updated = await controller.save(branchId: order.branch?.id);

    if (!context.mounted || updated == null) {
      return;
    }

    Navigator.of(context).pop(true);
  }
}

class _EditCartLine extends ConsumerWidget {
  const _EditCartLine({
    required this.order,
    required this.item,
    required this.enabled,
  });

  final OrderDetail order;
  final CartItem item;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editOrderControllerProvider(order).notifier);
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    final title = item.variant != null
        ? '${item.product.name} — ${item.variant!.name}'
        : item.product.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  '${item.quantity} × ${currency.format(item.unitPrice)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          pos_ui.IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            visualDensity: VisualDensity.compact,
            onPressed: enabled
                ? () => controller.decrementQuantity(item.lineKey)
                : null,
          ),
          Text('${item.quantity}'),
          pos_ui.IconButton(
            icon: const Icon(Icons.add_circle_outline),
            visualDensity: VisualDensity.compact,
            onPressed: enabled
                ? () => controller.incrementQuantity(item.lineKey)
                : null,
          ),
          SizedBox(
            width: 64,
            child: Text(
              currency.format(item.lineTotal),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController(
    text: widget.value > 0 ? widget.value.toStringAsFixed(2) : '',
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
                  if (widget.value > 0)
                    Text(
                      '- ${NumberFormat.currency(symbol: '\$').format(widget.value)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            pos_ui.OutlinedButton.icon(
              onPressed: widget.enabled
                  ? () => setState(() => _editing = true)
                  : null,
              icon: const Icon(Icons.discount_outlined),
              label: Text(widget.value > 0 ? 'Edit discount' : 'Add discount'),
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
              enabled: widget.enabled,
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
            onPressed: widget.enabled ? _apply : null,
          ),
        ],
      ),
    );
  }

  void _apply() {
    final value = double.tryParse(_controller.text) ?? 0;
    widget.onChanged(value);

    if (mounted) {
      setState(() => _editing = false);
    }
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value)],
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
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Could not load this order',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            pos_ui.PrimaryButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
