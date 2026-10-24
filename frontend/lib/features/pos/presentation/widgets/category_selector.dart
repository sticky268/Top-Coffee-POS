import 'package:flutter/material.dart';
import '../../../../core/theme/coffee_studio_theme.dart';

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
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    Widget chip(String name, int? id) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChoiceChip(
            avatar: CoffeeStudioTheme.active(context)
                ? Icon(
                    name.toLowerCase().contains('coffee')
                        ? Icons.local_cafe_outlined
                        : name.toLowerCase().contains('tea')
                            ? Icons.emoji_food_beverage_outlined
                            : name.toLowerCase().contains('bake')
                                ? Icons.bakery_dining_outlined
                                : Icons.grid_view_rounded,
                    size: 18)
                : null,
            label: Text(name),
            selected: selectedCategoryId == id,
            onSelected: (_) => onSelected(id),
            showCheckmark: false,
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: selectedCategoryId == id
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight:
                  selectedCategoryId == id ? FontWeight.w700 : FontWeight.w500,
            ),
            selectedColor: theme.colorScheme.primaryContainer,
            backgroundColor: CoffeeStudioTheme.active(context)
                ? CoffeeStudioTheme.accentSurface(context, id ?? 4)
                : theme.colorScheme.surface,
            side: BorderSide(
                color: selectedCategoryId == id
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
    return SizedBox(
      height: 64 + (textScale - 1).clamp(0, 3) * 24,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All', null),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            chip(category.name, category.id),
          ],
        ],
      ),
    );
  }
}
