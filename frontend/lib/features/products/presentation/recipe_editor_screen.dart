import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory_models.dart';
import '../data/products_repository.dart';
import '../domain/managed_product_models.dart';
import '../domain/recipe_models.dart';

class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key, required this.product});

  final ManagedProduct product;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  List<RecipeItem> _items = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecipe();
  }

  Future<void> _loadRecipe() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final branch = ref.read(currentBranchProvider);

      if (branch == null) {
        throw Exception('No branch is selected.');
      }

      final items = await ref
          .read(productsRepositoryProvider)
          .getRecipe(productId: widget.product.id!, branchId: branch.id);

      if (!mounted) return;

      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load recipe. Please try again.';
      });
    }
  }

  Future<void> _addIngredient() async {
    final branch = ref.read(currentBranchProvider);

    if (branch == null) {
      setState(() {
        _errorMessage = 'No branch is selected.';
      });
      return;
    }

    try {
      final ingredients = await ref
          .read(inventoryRepositoryProvider)
          .getIngredients(branchId: branch.id);

      if (!mounted) return;

      final availableIngredients = ingredients
          .where(
            (ingredient) =>
                !_items.any((item) => item.ingredientId == ingredient.id),
          )
          .toList();

      if (availableIngredients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'All available ingredients are already in this recipe.',
            ),
          ),
        );
        return;
      }

      final selectedIngredient = await showDialog<InventoryIngredient>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Add Ingredient'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: availableIngredients.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ingredient = availableIngredients[index];

                  return ListTile(
                    title: Text(ingredient.name),
                    subtitle: Text(
                      '${ingredient.currentStock} ${ingredient.unit.abbreviation} in stock',
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop(ingredient);
                    },
                  );
                },
              ),
            ),
            actions: [
              pos_ui.SecondaryButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if (!mounted || selectedIngredient == null) return;

      final quantity = await showDialog<double>(
        context: context,
        builder: (dialogContext) =>
            _RecipeQuantityDialog(ingredient: selectedIngredient),
      );

      if (!mounted || quantity == null) return;

      setState(() {
        _items = [
          ..._items,
          RecipeItem(
            ingredientId: selectedIngredient.id,
            ingredient: RecipeIngredient(
              id: selectedIngredient.id,
              name: selectedIngredient.name,
              unitId: selectedIngredient.unit.id,
              unitName: selectedIngredient.unit.name,
              unitAbbreviation: selectedIngredient.unit.abbreviation,
            ),
            quantityUsed: quantity,
          ),
        ];
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to load ingredients. Please try again.';
      });
    }
  }

  Future<void> _saveRecipe() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final branch = ref.read(currentBranchProvider);

      if (branch == null) {
        throw Exception('No branch is selected.');
      }

      final items = await ref
          .read(productsRepositoryProvider)
          .updateRecipe(
            productId: widget.product.id!,
            items: _items,
            branchId: branch.id,
          );

      if (!mounted) return;

      setState(() {
        _items = items;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipe saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save recipe. Please try again.';
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items = List<RecipeItem>.from(_items)..removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.product.name} Recipe')),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: pos_ui.PrimaryButton.icon(
          onPressed: _isLoading || _isSaving ? null : _saveRecipe,
          isLoading: _isSaving,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save Recipe'),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              pos_ui.OutlinedButton(
                onPressed: _loadRecipe,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.product.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Ingredients used for one sale',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (_items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No ingredients added yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          ...List.generate(
            _items.length,
            (index) => _RecipeItemCard(
              item: _items[index],
              onRemove: () => _removeItem(index),
            ),
          ),
        const SizedBox(height: 16),
        pos_ui.OutlinedButton.icon(
          onPressed: _addIngredient,
          icon: const Icon(Icons.add),
          label: const Text('Add Ingredient'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _RecipeItemCard extends StatelessWidget {
  const _RecipeItemCard({required this.item, required this.onRemove});

  final RecipeItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item.ingredient.name),
        subtitle: Text(
          '${item.quantityUsed} ${item.ingredient.unitAbbreviation}',
        ),
        trailing: pos_ui.IconButton(
          tooltip: 'Remove ingredient',
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

class _RecipeQuantityDialog extends StatefulWidget {
  const _RecipeQuantityDialog({required this.ingredient});

  final InventoryIngredient ingredient;

  @override
  State<_RecipeQuantityDialog> createState() => _RecipeQuantityDialogState();
}

class _RecipeQuantityDialogState extends State<_RecipeQuantityDialog> {
  final TextEditingController _quantityController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ingredient.name),
      content: TextField(
        controller: _quantityController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Quantity used',
          suffixText: widget.ingredient.unit.abbreviation,
          hintText: 'e.g. 18',
        ),
      ),
      actions: [
        pos_ui.SecondaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        pos_ui.PrimaryButton(
          onPressed: () {
            final value = double.tryParse(_quantityController.text.trim());
            if (value == null || value <= 0) return;
            Navigator.of(context).pop(value);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
