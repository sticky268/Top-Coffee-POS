import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/purchase_creation_controller.dart';
import '../application/purchase_creation_data_controller.dart';

class PurchaseCreationScreen extends ConsumerStatefulWidget {
  const PurchaseCreationScreen({super.key});

  @override
  ConsumerState<PurchaseCreationScreen> createState() =>
      _PurchaseCreationScreenState();
}

class _PurchaseCreationScreenState
    extends ConsumerState<PurchaseCreationScreen> {
  final _formKey = GlobalKey<FormState>();

  final Map<int, TextEditingController> _quantityControllers = {};
  final Map<int, TextEditingController> _unitCostControllers = {};

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }

    for (final controller in _unitCostControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  TextEditingController _quantityController(int ingredientId, double value) {
    return _quantityControllers.putIfAbsent(
      ingredientId,
      () => TextEditingController(text: value == 0 ? '' : value.toString()),
    );
  }

  TextEditingController _unitCostController(int ingredientId, double value) {
    return _unitCostControllers.putIfAbsent(
      ingredientId,
      () => TextEditingController(text: value == 0 ? '' : value.toString()),
    );
  }

  void _removeControllers(int ingredientId) {
    _quantityControllers.remove(ingredientId)?.dispose();
    _unitCostControllers.remove(ingredientId)?.dispose();
  }

  Future<void> _selectDate(PurchaseCreationState state) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: state.purchasedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (!mounted || selectedDate == null) {
      return;
    }

    ref
        .read(purchaseCreationControllerProvider.notifier)
        .setPurchasedAt(selectedDate);
  }

  Future<void> _addIngredient(
    PurchaseCreationData data,
    PurchaseCreationState state,
  ) async {
    final selectedIds = state.items.map((item) => item.ingredientId).toSet();

    final availableIngredients = data.ingredients
        .where((ingredient) => !selectedIds.contains(ingredient.id))
        .where((ingredient) => ingredient.isActive)
        .toList();

    if (availableIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No more ingredients are available to add.'),
        ),
      );
      return;
    }

    final selectedIngredient = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Add Ingredient'),
          children: availableIngredients.map((ingredient) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.of(dialogContext).pop(ingredient.id);
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ingredient.name),
                subtitle: Text(
                  'Stock: ${ingredient.currentStock} '
                  '${ingredient.unit.abbreviation}',
                ),
              ),
            );
          }).toList(),
        );
      },
    );

    if (!mounted || selectedIngredient == null) {
      return;
    }

    ref
        .read(purchaseCreationControllerProvider.notifier)
        .addIngredient(selectedIngredient);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final controller = ref.read(purchaseCreationControllerProvider.notifier);

    try {
      final purchase = await controller.save();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase #${purchase.id} saved successfully.')),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(purchaseCreationDataControllerProvider);
    final state = ref.watch(purchaseCreationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Purchase'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Refresh',
            onPressed: state.isSaving
                ? null
                : () => ref
                      .read(purchaseCreationDataControllerProvider.notifier)
                      .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _buildErrorState(error),
        data: (data) {
          if (data.suppliers.isEmpty) {
            return _buildNoSuppliersState();
          }

          if (data.ingredients.isEmpty) {
            return _buildNoIngredientsState();
          }

          return _buildForm(data, state);
        },
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Unable to load purchase data.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            pos_ui.PrimaryButton.icon(
              onPressed: () => ref
                  .read(purchaseCreationDataControllerProvider.notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSuppliersState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No suppliers are available for this branch.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildNoIngredientsState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No ingredients are available for this branch.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildForm(PurchaseCreationData data, PurchaseCreationState state) {
    final controller = ref.read(purchaseCreationControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Purchase Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<int>(
                  initialValue: state.supplierId,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: data.suppliers.map((supplier) {
                    return DropdownMenuItem<int>(
                      value: supplier.id,
                      child: Text(supplier.name),
                    );
                  }).toList(),
                  onChanged: state.isSaving ? null : controller.setSupplier,
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a supplier.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                pos_ui.ActionSurface(
                  onTap: state.isSaving ? null : () => _selectDate(state),
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Purchase Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(state.purchasedAt),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Purchase Items',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    pos_ui.PrimaryButton.icon(
                      onPressed: state.isSaving
                          ? null
                          : () => _addIngredient(data, state),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Ingredient'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 40),
                        SizedBox(height: 8),
                        Text(
                          'No ingredients added yet.',
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add the ingredients included in this purchase.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...state.items.map(
                    (item) =>
                        _buildItemCard(data, item, state.isSaving, controller),
                  ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Text(
                          'Total Cost',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          '\$${state.totalCost.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                        onPressed: state.isSaving ? null : _save,
                        child: state.isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Purchase'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(
    PurchaseCreationData data,
    PurchaseDraftItem item,
    bool isSaving,
    PurchaseCreationController controller,
  ) {
    final ingredient = data.ingredients.firstWhere(
      (ingredient) => ingredient.id == item.ingredientId,
    );

    final quantityController = _quantityController(
      item.ingredientId,
      item.quantity,
    );

    final unitCostController = _unitCostController(
      item.ingredientId,
      item.unitCost,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ingredient.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                pos_ui.IconButton(
                  tooltip: 'Remove ingredient',
                  onPressed: isSaving
                      ? null
                      : () {
                          _removeControllers(ingredient.id);
                          controller.removeIngredient(ingredient.id);
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Text(
              'Current stock: ${ingredient.currentStock} '
              '${ingredient.unit.abbreviation}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: quantityController,
                    enabled: !isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixText: ingredient.unit.abbreviation,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    validator: (value) {
                      final quantity = double.tryParse(value?.trim() ?? '');

                      if (quantity == null || quantity <= 0) {
                        return 'Enter a quantity greater than 0.';
                      }

                      return null;
                    },
                    onChanged: (value) {
                      final quantity = double.tryParse(value.trim()) ?? 0;

                      controller.updateQuantity(ingredient.id, quantity);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: unitCostController,
                    enabled: !isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit Cost',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final cost = double.tryParse(value?.trim() ?? '');

                      if (cost == null || cost < 0) {
                        return 'Enter a valid cost.';
                      }

                      return null;
                    },
                    onChanged: (value) {
                      final cost = double.tryParse(value.trim()) ?? 0;

                      controller.updateUnitCost(ingredient.id, cost);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Line Total: \$${item.lineTotal.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
