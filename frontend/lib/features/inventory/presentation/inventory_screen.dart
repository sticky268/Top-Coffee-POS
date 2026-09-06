import 'package:flutter/material.dart';

/// Placeholder for the Inventory screen — built out in a later phase.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('Inventory — coming soon', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
