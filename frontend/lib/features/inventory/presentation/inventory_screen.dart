import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/subscription/subscription_action_guard.dart';

import '../application/inventory_list_controller.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryIngredient> _filteredIngredients(
    List<InventoryIngredient> ingredients,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return ingredients;
    }

    return ingredients.where((ingredient) {
      return ingredient.name.toLowerCase().contains(query) ||
          ingredient.unit.name.toLowerCase().contains(query) ||
          ingredient.unit.abbreviation.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryState = ref.watch(inventoryListControllerProvider);
    final canModify = SubscriptionActionGuard.canModify(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
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
      body: inventoryState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () =>
              ref.read(inventoryListControllerProvider.notifier).refresh(),
        ),
        data: (data) {
          final ingredients = _filteredIngredients(data.ingredients);

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
                  onAddIngredient: canModify
                      ? () {
                          context.push('/inventory/add');
                        }
                      : null,
                ),
                const SizedBox(height: 20),
                if (data.ingredients.isEmpty)
                  const _EmptyState()
                else if (ingredients.isEmpty)
                  const _NoSearchResults()
                else
                  ...ingredients.map(
                    (ingredient) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _IngredientCard(
                        ingredient: ingredient,
                        onEdit: canModify
                            ? () => context.push(
                                  '/inventory/edit',
                                  extra: ingredient,
                                )
                            : null,
                        onStockAction: canModify
                            ? () => _showStockActionDialog(ingredient)
                            : null,
                        onDelete: canModify
                            ? () => _deleteIngredient(ingredient)
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
    );
  }

  Future<void> _deleteIngredient(
    InventoryIngredient ingredient,
  ) async {
    if (!SubscriptionActionGuard.canModify(ref)) {
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
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final repository = ref.read(inventoryRepositoryProvider);

      await repository.deleteIngredient(
        ingredientId: ingredient.id,
      );

      if (!mounted) return;

      ref.invalidate(inventoryListControllerProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ingredient.name} deleted successfully.'),
        ),
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
    InventoryIngredient ingredient,
  ) async {
    String type = 'purchase';
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();

    bool isSaving = false;
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isSaving,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              Future<void> submit() async {
                final quantity = double.tryParse(
                  quantityController.text.trim(),
                );

                if (quantity == null || quantity <= 0) {
                  setState(() {
                    errorMessage =
                        'Please enter a valid quantity greater than 0.';
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
                  if (!mounted) return;

                  setState(() {
                    isSaving = false;
                    errorMessage = error.toString();
                  });
                }
              }

              return AlertDialog(
                title: Text('Stock Action - ${ingredient.name}'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(
                          labelText: 'Action',
                        ),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
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
                        const SizedBox(height: 12),
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
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isSaving ? null : submit,
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Continue'),
                  ),
                ],
              );
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Stock',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
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
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
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
        : ingredient.isLowStock
            ? 'Low Stock'
            : 'In Stock';

    final statusColor = !ingredient.isActive
        ? theme.colorScheme.outline
        : ingredient.isLowStock
            ? theme.colorScheme.error
            : Colors.green;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
            Expanded(
              child: Column(
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
              ),
            ),
            const SizedBox(width: 16),
            Column(
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                      ),
                      label: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onStockAction,
                      icon: const Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                      ),
                      label: const Text('Stock Action'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onHistory,
                      icon: const Icon(
                        Icons.history,
                        size: 18,
                      ),
                      label: const Text('History'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                      ),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ],
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
            const SizedBox(height: 12),
            Text(
              'No ingredients yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Add your first ingredient to start tracking stock.',
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
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 300,
      child: Center(
        child: Text('No ingredients match your search.'),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
            const Icon(
              Icons.error_outline,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load inventory.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
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
