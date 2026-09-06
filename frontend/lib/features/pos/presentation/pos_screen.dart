import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/pos_catalog_controller.dart';
import '../application/pos_catalog_state.dart';
import '../domain/pos_models.dart';
import 'widgets/cart_panel.dart';
import 'widgets/category_selector.dart';
import 'widgets/product_grid.dart';
import 'widgets/product_search_field.dart';

/// The cashier's New Order screen — category tabs, product grid, and cart,
/// in a layout that adapts between a phone (stacked vertically) and a
/// tablet/desktop (two-panel) arrangement. Replaces the Phase 4 placeholder.
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(posCatalogControllerProvider);

    return PopScope(
      // Unconditional, unlike relying on Navigator.canPop(): the "New
      // Order" button on the post-checkout confirmation screen reaches
      // this route via context.go('/pos'), which replaces the stack —
      // there's nothing to pop in that case, so the default back-button
      // behavior would silently do nothing. Explicitly redirecting here
      // makes system back behave the same regardless of how /pos was
      // reached.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Dashboard',
            onPressed: () => context.go('/home'),
          ),
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
                    onRetry: () => ref.read(posCatalogControllerProvider.notifier).refresh(),
                  ),
                PosCatalogLoaded(:final categories, :final selectedCategoryId, :final visibleProducts) =>
                  isCompact
                      ? _PhoneLayout(
                          categories: categories,
                          selectedCategoryId: selectedCategoryId,
                          products: visibleProducts,
                          crossAxisCount: productColumns,
                        )
                      : _TabletLayout(
                          categories: categories,
                          selectedCategoryId: selectedCategoryId,
                          products: visibleProducts,
                          crossAxisCount: productColumns,
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
  });

  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SizedBox(height: 12),
        ProductSearchField(
          onChanged: (query) => ref.read(posCatalogControllerProvider.notifier).updateSearchQuery(query),
        ),
        const SizedBox(height: 8),
        CategorySelector(
          categories: categories,
          selectedCategoryId: selectedCategoryId,
          onSelected: (id) => ref.read(posCatalogControllerProvider.notifier).selectCategory(id),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: ProductGrid(products: products, crossAxisCount: crossAxisCount),
        ),
        const Divider(height: 1),
        const Expanded(
          flex: 2,
          child: CartPanel(),
        ),
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
  });

  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final List<PosProduct> products;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              const SizedBox(height: 12),
              ProductSearchField(
                onChanged: (query) => ref.read(posCatalogControllerProvider.notifier).updateSearchQuery(query),
              ),
              const SizedBox(height: 8),
              CategorySelector(
                categories: categories,
                selectedCategoryId: selectedCategoryId,
                onSelected: (id) => ref.read(posCatalogControllerProvider.notifier).selectCategory(id),
              ),
              const SizedBox(height: 8),
              Expanded(child: ProductGrid(products: products, crossAxisCount: crossAxisCount)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const SizedBox(width: 340, child: CartPanel()),
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
            const SizedBox(height: 12),
            Text('Could not load the menu', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
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
