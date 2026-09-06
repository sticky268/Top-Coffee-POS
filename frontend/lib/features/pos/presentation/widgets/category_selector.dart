import 'package:flutter/material.dart';

import '../../domain/pos_models.dart';

class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<PosCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selectedCategoryId == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(category.name),
              selected: selectedCategoryId == category.id,
              onSelected: (_) => onSelected(category.id),
            ),
          ],
        ],
      ),
    );
  }
}
