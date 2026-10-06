import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/subscription/subscription_action_guard.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../pos/domain/pos_models.dart';
import '../../pos/presentation/widgets/category_selector.dart';
import '../../pos/presentation/widgets/product_search_field.dart';
import '../application/products_controller.dart';
import '../application/products_state.dart';
import '../data/products_repository.dart';
import '../domain/managed_product_models.dart';
import 'product_form_screen.dart';
import 'widgets/product_list_tile.dart';

/// Real, API-backed Products browsing + management screen — replaces the
/// Phase 4 placeholder. Reached from the dashboard's "Products" quick
/// action (unchanged) via the existing `/products` route (unchanged).
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productsControllerProvider);
    final canModify = SubscriptionActionGuard.canModify(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          if (state is ProductsLoaded)
            pos_ui.IconButton(
              onPressed: () {
                context.push('/products/categories');
              },
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Manage Categories',
            ),
        ],
      ),
      // Only shown once categories are actually loaded — the Add Product
      // form needs them for its category dropdown, and this screen is
      // the only place that data comes from (no second fetch).
      floatingActionButton: state is ProductsLoaded
          ? FloatingActionButton.extended(
              onPressed: canModify
                  ? () => context.push(
                      '/products/form',
                      extra: ProductFormArgs(categories: state.categories),
                    )
                  : null,
              tooltip: canModify ? 'Add Product' : 'Subscription is read-only',
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
      body: switch (state) {
        ProductsLoading() => const Center(child: CircularProgressIndicator()),
        ProductsError(:final message) => _ProductsErrorView(
          message: message,
          onRetry: () =>
              ref.read(productsControllerProvider.notifier).refresh(),
        ),
        ProductsLoaded loaded => _ProductsBody(
          state: loaded,
          canModify: canModify,
        ),
      },
    );
  }
}

class _ProductsBody extends ConsumerStatefulWidget {
  const _ProductsBody({required this.state, required this.canModify});

  final ProductsLoaded state;
  final bool canModify;

  @override
  ConsumerState<_ProductsBody> createState() => _ProductsBodyState();
}

class _ProductsBodyState extends ConsumerState<_ProductsBody> {
  // Tracks which products currently have an in-flight disable request —
  // per-row, not a single screen-wide flag, so disabling one product
  // doesn't block interacting with the rest of the list.
  final Set<int> _disablingIds = {};

  Future<void> _confirmAndDisable(PosProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Product?'),
        content: Text(
          '"${product.name}" will no longer appear in the catalog. Its data and any order history are kept — '
          'it is not deleted.',
        ),
        actions: [
          pos_ui.SecondaryButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          pos_ui.PrimaryButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _disablingIds.add(product.id));

    try {
      // Direct repository call for this one-shot toggle, not routed
      // through a StateNotifier — matches the existing "Clear Cart"-style
      // pattern elsewhere in the app (confirm dialog + direct call +
      // feedback), rather than building a dedicated state machine for a
      // single fire-and-forget action.
      await ref
          .read(productsRepositoryProvider)
          .setProductActive(product.id, false);
      if (!mounted) return;
      ref.read(productsControllerProvider.notifier).refresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${product.name}" disabled')));
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Could not disable this product';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _disablingIds.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.state.visibleProducts;

    return RefreshIndicator(
      onRefresh: () => ref.read(productsControllerProvider.notifier).refresh(),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _SearchAndCategoryRow(state: widget.state),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? ListView(
                    // Kept scrollable (even though empty) so
                    // pull-to-refresh still works from this state.
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _EmptyProducts(isFiltered: widget.state.isFiltered),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = visible[index];
                      return ProductListTile(
                        product: product,
                        canModify: widget.canModify,
                        isDisabling: _disablingIds.contains(product.id),
                        onEdit: () => context.push(
                          '/products/form',
                          extra: ProductFormArgs(
                            categories: widget.state.categories,
                            initialProduct: ManagedProduct.fromPosProduct(
                              product,
                            ),
                          ),
                        ),
                        onDisable: () => _confirmAndDisable(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Existing search field + category selector — unchanged in behavior,
/// only pulled into a small widget so _ProductsBody's build() method
/// isn't overly long.
class _SearchAndCategoryRow extends ConsumerWidget {
  const _SearchAndCategoryRow({required this.state});

  final ProductsLoaded state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ProductSearchField(
          onChanged: (query) => ref
              .read(productsControllerProvider.notifier)
              .updateSearchQuery(query),
        ),
        const SizedBox(height: 8),
        CategorySelector(
          categories: state.categories,
          selectedCategoryId: state.selectedCategoryId,
          onSelected: (id) =>
              ref.read(productsControllerProvider.notifier).selectCategory(id),
        ),
      ],
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.isFiltered});

  /// Distinguishes "nothing matches your search/filter" from "this branch
  /// genuinely has no products yet" — different messages for a clearer
  /// empty state, per the task's "clearly explain" requirement.
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? Icons.search_off : Icons.local_cafe_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching products found' : 'No products available',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Try a different search or category'
                : 'Check back once products are added',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsErrorView extends StatelessWidget {
  const _ProductsErrorView({required this.message, required this.onRetry});

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
            Text('Could not load products', style: theme.textTheme.titleMedium),
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
