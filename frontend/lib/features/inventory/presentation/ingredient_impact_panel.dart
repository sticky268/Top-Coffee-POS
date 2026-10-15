import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/inventory_list_controller.dart';
import '../data/ingredient_impact.dart';

/// Queries only when expanded, with at most 20 names shown per request.
/// It presents recorded dependencies, never a claim about servings available.
class IngredientImpactPanel extends ConsumerStatefulWidget {
  const IngredientImpactPanel({
    super.key, required this.ingredientId, required this.scope,
  });
  final int ingredientId;
  final InventoryScope scope;

  @override
  ConsumerState<IngredientImpactPanel> createState() => _IngredientImpactPanelState();
}

class _IngredientImpactPanelState extends ConsumerState<IngredientImpactPanel> {
  bool _expanded = false;
  int? _afterId;
  final List<int?> _history = [];

  @override
  Widget build(BuildContext context) {
    if (ref.watch(inventoryScopeProvider) != widget.scope) {
      return const SizedBox.shrink();
    }
    final query = (
      ingredientId: widget.ingredientId, scope: widget.scope, afterId: _afterId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pos_ui.SecondaryButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(_expanded
              ? 'Hide products using this ingredient'
              : 'Show products using this ingredient'),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          const Text(
            'Includes optional modifiers. Recorded recipe links do not determine whether a product can be sold.',
          ),
          const SizedBox(height: 8),
          ref.watch(ingredientImpactProvider(query)).when(
            skipLoadingOnReload: false,
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                SizedBox.square(dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Expanded(child: Text('Checking recipe links…')),
              ]),
            ),
            error: (error, stack) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Could not load recipe links. Stock has not changed.'),
                pos_ui.OutlinedButton(
                  onPressed: () => ref.invalidate(ingredientImpactProvider(query)),
                  child: const Text('Retry recipe links'),
                ),
              ],
            ),
            data: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.products.isEmpty)
                  const Text(
                    'No active products in this branch have a recorded recipe link. Unrecorded recipes are not checked.',
                  )
                else
                  ...page.products.map((product) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• ${product.name}'),
                  )),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    if (_history.isNotEmpty)
                      pos_ui.OutlinedButton(
                        onPressed: () => setState(() => _afterId = _history.removeLast()),
                        child: const Text('Previous products'),
                      ),
                    if (page.nextAfterId != null)
                      pos_ui.OutlinedButton(
                        onPressed: () => setState(() {
                          _history.add(_afterId);
                          _afterId = page.nextAfterId;
                        }),
                        child: const Text('Next products'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
