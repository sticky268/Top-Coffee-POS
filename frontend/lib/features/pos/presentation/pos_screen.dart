import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/receipt/last_receipt_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../core/widgets/receipt_action_buttons.dart';
import '../application/pos_catalog_controller.dart';
import '../application/pos_catalog_state.dart';
import '../domain/pos_models.dart';
import 'widgets/cart_panel.dart';
import 'widgets/category_selector.dart';
import 'widgets/product_grid.dart';
import 'widgets/product_search_field.dart';

/// The cashier's New Order screen ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â category tabs, product grid, and cart,
/// in a layout that adapts between a phone (stacked vertically) and a
/// tablet/desktop (two-panel) arrangement.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, this.initialTable});

  final PosTable? initialTable;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  PosTable? _selectedTable;
  int? _selectedBranchId;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = ref.read(currentBranchProvider)?.id;
    _selectedTable = widget.initialTable;
    if (_selectedTable?.branchId != null &&
        _selectedTable!.branchId != _selectedBranchId) {
      _selectedTable = null;
    }
  }

  Future<void> _openTableSelector() async {
    final table = await context.push<PosTable>('/pos/select-table');

    if (table != null && mounted) {
      setState(() {
        _selectedTable = table;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(posCatalogControllerProvider);
    final lastReceipt = ref.watch(lastCompletedOrderProvider).asData?.value;
    ref.listen(currentBranchProvider, (previous, next) {
      if (previous?.id == next?.id) return;
      _selectedBranchId = next?.id;
      if (_selectedTable != null && mounted) {
        setState(() {
          _selectedTable = null;
        });
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Order'),
          leading: pos_ui.IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Dashboard',
            onPressed: () => context.go('/home'),
          ),
          actions: [
            pos_ui.SecondaryButton.icon(
              onPressed: lastReceipt == null
                  ? null
                  : () => showLastReceiptDialog(
                        context: context,
                        orderId: lastReceipt.id,
                        orderReference: lastReceipt.displayOrderReference,
                      ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Last Receipt'),
            ),
            const SizedBox(width: 8),
            pos_ui.SecondaryButton.icon(
              onPressed: _openTableSelector,
              icon: const Icon(Icons.table_restaurant),
              label: const Text('Dine-in'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 600;
              final productColumns = constraints.maxWidth >= 1024
                  ? 4
                  : (constraints.maxWidth >= 600 ? 3 : 2);

              return switch (catalogState) {
                PosCatalogLoading() => const _CatalogLoading(),
                PosCatalogError(:final message) => _CatalogErrorView(
                  message: message,
                  onRetry: () =>
                      ref.read(posCatalogControllerProvider.notifier).refresh(),
                ),
                PosCatalogLoaded(
                  :final categories,
                  :final selectedCategoryId,
                  :final visibleProducts,
                ) =>
                  isCompact
                      ? _PhoneLayout(
                          categories: categories,
                          selectedCategoryId: selectedCategoryId,
                          products: visibleProducts,
                          crossAxisCount: productColumns,
                          selectedTable: _selectedTable,
                        )
                      : _TabletLayout(
                          categories: categories,
                          selectedCategoryId: selectedCategoryId,
                          products: visibleProducts,
                          crossAxisCount: productColumns,
                          selectedTable: _selectedTable,
                        ),
              };
            },
          ),
        ),
      ),
    );
  }
}

class _PhoneLayout extends ConsumerWidget {
  const _PhoneLayout({
    required this.categories,
    required this.selectedCategoryId,
    required this.products,
    required this.crossAxisCount,
    required this.selectedTable,
  });

  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;
  final int crossAxisCount;
  final PosTable? selectedTable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          flex: 3,
          child: ProductGrid(
            products: products,
            crossAxisCount: crossAxisCount,
          ),
        ),
        const Divider(height: 1),
        Expanded(flex: 2, child: CartPanel(selectedTable: selectedTable)),
      ],
    );
  }
}

class _TabletLayout extends ConsumerWidget {
  const _TabletLayout({
    required this.categories,
    required this.selectedCategoryId,
    required this.products,
    required this.crossAxisCount,
    required this.selectedTable,
  });

  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;
  final int crossAxisCount;
  final PosTable? selectedTable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
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
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 340, child: CartPanel(selectedTable: selectedTable)),
      ],
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _CatalogErrorView extends StatelessWidget {
  const _CatalogErrorView({required this.message, required this.onRetry});

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
            Text('Could not load the menu', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
