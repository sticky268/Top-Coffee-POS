import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

class InventoryMovementHistoryScreen extends ConsumerStatefulWidget {
  const InventoryMovementHistoryScreen({
    super.key,
    required this.ingredient,
  });

  final InventoryIngredient ingredient;

  @override
  ConsumerState<InventoryMovementHistoryScreen> createState() =>
      _InventoryMovementHistoryScreenState();
}

class _InventoryMovementHistoryScreenState
    extends ConsumerState<InventoryMovementHistoryScreen> {
  String? _selectedType;
  bool _isLoading = true;
  String? _errorMessage;
  List<InventoryStockMovement> _movements = [];

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final movements =
          await ref.read(inventoryRepositoryProvider).getStockMovements(
                ingredientId: widget.ingredient.id,
                type: _selectedType,
              );

      if (!mounted) return;

      setState(() {
        _movements = movements;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'purchase':
        return 'Stock In / Purchase';
      case 'adjustment':
        return 'Adjustment';
      case 'wastage':
        return 'Wastage';
      case 'sale_deduction':
        return 'Sale Deduction';
      default:
        return type;
    }
  }

  Color _quantityColor(BuildContext context, double quantity) {
    if (quantity > 0) {
      return Colors.green;
    }

    if (quantity < 0) {
      return Theme.of(context).colorScheme.error;
    }

    return Theme.of(context).colorScheme.outline;
  }

  String _formatQuantity(double quantity) {
    final sign = quantity > 0 ? '+' : '';
    return '$sign${quantity.toStringAsFixed(3)} '
        '${widget.ingredient.unit.abbreviation}';
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();

    final year = local.year.toString();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.ingredient.name} History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadMovements,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Movement Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All movements'),
                ),
                DropdownMenuItem<String?>(
                  value: 'purchase',
                  child: Text('Stock In / Purchase'),
                ),
                DropdownMenuItem<String?>(
                  value: 'adjustment',
                  child: Text('Adjustment'),
                ),
                DropdownMenuItem<String?>(
                  value: 'wastage',
                  child: Text('Wastage'),
                ),
                DropdownMenuItem<String?>(
                  value: 'sale_deduction',
                  child: Text('Sale Deduction'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
                _loadMovements();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Current Stock'),
                trailing: Text(
                  '${widget.ingredient.currentStock.toStringAsFixed(3)} '
                  '${widget.ingredient.unit.abbreviation}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
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
                'Could not load movement history.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadMovements,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_movements.isEmpty) {
      return const Center(
        child: Text('No stock movements found.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMovements,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _movements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final movement = _movements[index];
          final quantityColor = _quantityColor(
            context,
            movement.quantity,
          );

          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: quantityColor.withValues(alpha: 0.12),
                    child: Icon(
                      movement.quantity >= 0
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: quantityColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel(movement.type),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(movement.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (movement.reason != null &&
                            movement.reason!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            movement.reason!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Balance after: '
                          '${movement.balanceAfter.toStringAsFixed(3)} '
                          '${widget.ingredient.unit.abbreviation}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatQuantity(movement.quantity),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: quantityColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
