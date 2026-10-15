import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../../core/subscription/subscription_action_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/inventory_list_controller.dart';
import '../application/inventory_attention.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.initialLowStockOnly = false});

  final bool initialLowStockOnly;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();

  String _searchQuery = '';
  late InventoryStockFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialLowStockOnly
        ? InventoryStockFilter.needsRestock
        : InventoryStockFilter.all;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryState = ref.watch(inventoryListControllerProvider);
    final canModify = SubscriptionActionGuard.canModify(ref);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final selectedBranch = ref.watch(currentBranchProvider);
    final scope = ref.watch(inventoryScopeProvider);
    final canManage = canModify && scope != null &&
        user?.hasPermission('inventory.manage') == true;
    final canAdjust = canModify && scope != null &&
        user?.hasPermission('inventory.adjust') == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Refresh',
            onPressed: inventoryState.isLoading
                ? null
                : () => ref
                      .read(inventoryListControllerProvider.notifier)
                      .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PageContent(
        maxWidth: 1000,
        child: inventoryState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: error.toString(),
            onRetry: () =>
                ref.read(inventoryListControllerProvider.notifier).refresh(),
          ),
          data: (data) {
            final ingredients = inventoryAttentionList(
              data.ingredients, query: _searchQuery, filter: _filter,
            );
            final summary = InventoryAttentionSummary(data.ingredients);

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(inventoryListControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _InventoryHeader(
                    searchController: _searchController,
                    onSearchChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    onAddIngredient: canManage
                        ? () {
                            context.push('/inventory/add');
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedBranch == null ? 'Select a branch' : selectedBranch.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${summary.outOfStock} out of stock · '
                    '${summary.needsRestock} need restocking. '
                    'Stock changes are recorded in movement history.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('All (${data.ingredients.length})'),
                        selected: _filter == InventoryStockFilter.all,
                        onSelected: (_) => setState(() => _filter = InventoryStockFilter.all),
                      ),
                      ChoiceChip(
                        label: Text('Needs restock (${summary.needsRestock})'),
                        selected: _filter == InventoryStockFilter.needsRestock,
                        onSelected: (_) => setState(() => _filter = InventoryStockFilter.needsRestock),
                      ),
                      ChoiceChip(
                        label: Text('Inactive (${summary.inactive})'),
                        selected: _filter == InventoryStockFilter.inactive,
                        onSelected: (_) => setState(() => _filter = InventoryStockFilter.inactive),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (data.ingredients.isEmpty)
                    const _EmptyState()
                  else if (ingredients.isEmpty)
                    _NoSearchResults(filter: _filter, hasSearch: _searchQuery.trim().isNotEmpty)
                  else
                    ...ingredients.map(
                      (ingredient) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _IngredientCard(
                          ingredient: ingredient,
                          onEdit: canManage && data.scope == scope
                              ? () => context.push(
                                  '/inventory/edit',
                                  extra: ingredient,
                                )
                              : null,
                          onStockAction: canAdjust && data.scope == scope
                              ? () => _showStockActionDialog(ingredient, data.scope)
                              : null,
                          onDelete: canManage && data.scope == scope
                              ? () => _deleteIngredient(ingredient, data.scope)
                              : null,
                          onHistory: () => context.push(
                            '/inventory/history',
                            extra: ingredient,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteIngredient(
    InventoryIngredient ingredient, InventoryScope? selected,
  ) async {
    final auth = ref.read(authControllerProvider);
    if (selected == null || ref.read(inventoryScopeProvider) != selected ||
        auth is! AuthAuthenticated ||
        !auth.user.hasPermission('inventory.manage') ||
        !SubscriptionActionGuard.canModify(ref)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Ingredient?'),
          content: Text(
            'Are you sure you want to delete "${ingredient.name}"? '
            'The ingredient will be removed from active inventory, but '
            'its stock history will be preserved.',
          ),
          actions: [
            pos_ui.SecondaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            pos_ui.DangerButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted ||
        ref.read(inventoryScopeProvider) != selected) {
      return;
    }

    final currentAuth = ref.read(authControllerProvider);
    if (currentAuth is! AuthAuthenticated ||
        !currentAuth.user.hasPermission('inventory.manage') ||
        !SubscriptionActionGuard.canModify(ref)) {
      return;
    }

    try {
      final repository = ref.read(inventoryRepositoryProvider);

      await repository.deleteIngredient(ingredientId: ingredient.id);

      if (!mounted || ref.read(inventoryScopeProvider) != selected) return;

      ref.invalidate(inventoryListControllerProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ingredient.name} deleted successfully.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ValidationException
                ? error.message
                : 'Could not delete ${ingredient.name}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showStockActionDialog(
    InventoryIngredient ingredient, InventoryScope? selected,
  ) async {
    final auth = ref.read(authControllerProvider);
    if (selected == null || ref.read(inventoryScopeProvider) != selected ||
        auth is! AuthAuthenticated ||
        !auth.user.hasPermission('inventory.adjust') ||
        !SubscriptionActionGuard.canModify(ref)) {
      return;
    }
    String type = 'purchase';
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();

    bool isSaving = false;
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              Future<void> submit() async {
                if (isSaving) return;
                final currentAuth = ref.read(authControllerProvider);
                if (ref.read(inventoryScopeProvider) != selected ||
                    currentAuth is! AuthAuthenticated ||
                    !currentAuth.user.hasPermission('inventory.adjust') ||
                    !SubscriptionActionGuard.canModify(ref)) {
                  setState(() => errorMessage =
                      'Account or branch changed. Close this form and reopen it for the current branch.');
                  return;
                }
                final quantity = double.tryParse(
                  quantityController.text.trim(),
                );

                if (quantity == null ||
                    !quantity.isFinite ||
                    quantity == 0 ||
                    (type != 'adjustment' && quantity < 0)) {
                  setState(() {
                    errorMessage = type == 'adjustment'
                        ? 'Enter a non-zero quantity. Use a negative number to reduce stock.'
                        : 'Please enter a valid quantity greater than 0.';
                  });
                  return;
                }

                final quantityText = quantityController.text.trim();
                if (!RegExp(r'^-?\d+(\.\d{1,3})?$').hasMatch(quantityText)) {
                  setState(() => errorMessage =
                      'Use a quantity with no more than 3 decimal places.');
                  return;
                }

                if ((type == 'adjustment' || type == 'wastage') &&
                    reasonController.text.trim().isEmpty) {
                  setState(() {
                    errorMessage = 'Please enter a reason for this stock action.';
                  });
                  return;
                }

                setState(() {
                  isSaving = true;
                  errorMessage = null;
                });

                try {
                  final repository = ref.read(inventoryRepositoryProvider);

                  await repository.recordStockMovement(
                    ingredientId: ingredient.id,
                    type: type,
                    quantity: quantity,
                    reason: reasonController.text,
                  );

                  if (!mounted) return;

                  ref.invalidate(inventoryListControllerProvider);

                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                } catch (error) {
                  if (!mounted || !dialogContext.mounted) return;

                  setState(() {
                    isSaving = false;
                    errorMessage = error.toString();
                  });
                }
              }

              return PopScope(
                canPop: !isSaving,
                child: AlertDialog(
                title: Text('Record stock movement — ${ingredient.name}'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'Action'),
                        items: const [
                          DropdownMenuItem(
                            value: 'purchase',
                            child: Text('Stock In / Purchase'),
                          ),
                          DropdownMenuItem(
                            value: 'adjustment',
                            child: Text('Adjustment'),
                          ),
                          DropdownMenuItem(
                            value: 'wastage',
                            child: Text('Wastage'),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    type = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: quantityController,
                        enabled: !isSaving,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true, signed: type == 'adjustment',
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity',
                          suffixText: ingredient.unit.abbreviation,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: reasonController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          hintText: 'Optional for stock in',
                        ),
                        maxLines: 2,
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  pos_ui.SecondaryButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  pos_ui.PrimaryButton(
                    onPressed: isSaving ? null : submit,
                    isLoading: isSaving,
                    child: const Text('Continue'),
                  ),
                ],
              ));
            },
          );
        },
      );
    } finally {
      quantityController.dispose();
      reasonController.dispose();
    }
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.onAddIngredient,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onAddIngredient;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Text('Stock', style: Theme.of(context).textTheme.headlineSmall),
            pos_ui.PrimaryButton.icon(
              onPressed: onAddIngredient,
              icon: const Icon(Icons.add),
              label: const Text('Add Ingredient'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search ingredients...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchController.text.isEmpty
                ? null
                : pos_ui.IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    required this.ingredient,
    required this.onEdit,
    required this.onStockAction,
    required this.onDelete,
    required this.onHistory,
  });

  final InventoryIngredient ingredient;
  final VoidCallback? onEdit;
  final VoidCallback? onStockAction;
  final VoidCallback? onDelete;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusText = !ingredient.isActive
        ? 'Inactive'
        : ingredient.currentStock <= 0
        ? 'Out of Stock'
        : ingredient.isLowStock
        ? 'Low Stock'
        : 'In Stock';

    final statusColor = !ingredient.isActive
        ? theme.colorScheme.outline
        : ingredient.isLowStock || ingredient.currentStock <= 0
        ? theme.colorScheme.error
        : AppColors.semantic(context, AppColors.success);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ingredient.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Reorder at ${ingredient.reorderThreshold.toStringAsFixed(3)} ${ingredient.unit.abbreviation}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    final stock = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${ingredient.currentStock.toStringAsFixed(3)} ${ingredient.unit.abbreviation}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            pos_ui.OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            pos_ui.OutlinedButton.icon(
              onPressed: onStockAction,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(ingredient.isActive &&
                      (ingredient.isLowStock || ingredient.currentStock <= 0)
                  ? 'Restock / adjust'
                  : 'Record movement'),
            ),
            pos_ui.OutlinedButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history, size: 18),
              label: const Text('History'),
            ),
            pos_ui.DangerButton.outlinedIcon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heading = Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 16), stock],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                SizedBox(width: 560, child: stock),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No ingredients yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Ingredients added for this branch appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.filter, required this.hasSearch});
  final InventoryStockFilter filter;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(child: Text(hasSearch
          ? 'No ingredients match this search and filter.'
          : filter == InventoryStockFilter.needsRestock
          ? 'No active ingredients need restocking.'
          : 'No inactive ingredients.')),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load inventory.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
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
