import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/subscription/subscription_action_guard.dart';

import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';
import '../application/inventory_list_controller.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({super.key});

  @override
  ConsumerState<AddIngredientScreen> createState() =>
      _AddIngredientScreenState();
}

class _AddIngredientScreenState extends ConsumerState<AddIngredientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _thresholdController = TextEditingController(text: '0');

  List<InventoryUnit> _units = const [];
  InventoryUnit? _selectedUnit;

  bool _isLoadingUnits = true;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    try {
      final repository = ref.read(inventoryRepositoryProvider);
      final units = await repository.getUnits();

      if (!mounted) return;

      setState(() {
        _units = units;
        _selectedUnit = units.isEmpty ? null : units.first;
        _isLoadingUnits = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoadingUnits = false;
      });
    }
  }

  Future<void> _save() async {
    if (!SubscriptionActionGuard.canModify(ref)) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedUnit == null) {
      setState(() {
        _errorMessage = 'Please select a unit.';
      });
      return;
    }

    final threshold = double.tryParse(_thresholdController.text.trim());

    if (threshold == null || threshold < 0) {
      setState(() {
        _errorMessage = 'Please enter a valid reorder threshold.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(inventoryRepositoryProvider);

      await repository.createIngredient(
        name: _nameController.text.trim(),
        unitId: _selectedUnit!.id,
        reorderThreshold: threshold,
        isActive: _isActive,
      );

      if (!mounted) return;

      ref.invalidate(inventoryListControllerProvider);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Ingredient'),
      ),
      body: _isLoadingUnits
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _units.isEmpty
              ? _buildNoUnitsState()
              : _buildForm(),
    );
  }

  Widget _buildNoUnitsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'No units are available.',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadUnits,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final canModify = SubscriptionActionGuard.canModify(ref);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ingredient Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving && canModify,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Ingredient Name',
                    hintText: 'e.g. Coffee Beans',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingredient name is required.';
                    }

                    if (value.trim().length > 255) {
                      return 'Ingredient name is too long.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<InventoryUnit>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    prefixIcon: Icon(Icons.straighten_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _units.map((unit) {
                    return DropdownMenuItem<InventoryUnit>(
                      value: unit,
                      child: Text(
                        '${unit.name} (${unit.abbreviation})',
                      ),
                    );
                  }).toList(),
                  onChanged: _isSaving || !canModify
                      ? null
                      : (unit) {
                          setState(() {
                            _selectedUnit = unit;
                          });
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _thresholdController,
                  enabled: !_isSaving && canModify,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Reorder Threshold',
                    hintText: 'e.g. 2',
                    prefixIcon: Icon(Icons.warning_amber_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final number = double.tryParse(value?.trim() ?? '');

                    if (number == null || number < 0) {
                      return 'Enter a valid threshold.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'When stock reaches this level, the ingredient will be '
                  'marked as low stock.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Allow this ingredient to be used for inventory tracking.',
                  ),
                  value: _isActive,
                  onChanged: _isSaving || !canModify
                      ? null
                      : (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSaving || !canModify ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Ingredient'),
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
}
