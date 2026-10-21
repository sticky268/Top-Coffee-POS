import 'package:flutter/material.dart';
import '../../domain/pos_models.dart';

Future<CartItem?> showMenuSelection(
  BuildContext context,
  PosProduct product, {
  List<PosProduct> catalog = const [],
}) => showModalBottomSheet<CartItem>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _MenuSelection(product: product, catalog: catalog),
);

class _MenuSelection extends StatefulWidget {
  const _MenuSelection({required this.product, required this.catalog});
  final PosProduct product;
  final List<PosProduct> catalog;
  @override
  State<_MenuSelection> createState() => _MenuSelectionState();
}

class _MenuSelectionState extends State<_MenuSelection> {
  final form = GlobalKey<FormState>();
  final Set<int> modifiers = {};
  final Map<int, int> components = {};
  PosProductVariant? variant;
  int cents(dynamic value) => ((num.tryParse('$value') ?? 0) * 100).round();
  String choiceName(Map choice) {
    final found = widget.catalog.where((p) => p.id == choice['product_id']);
    if (found.isEmpty) return 'Unavailable item';
    final product = found.first;
    final variants = product.variants.where(
      (v) => v.id == choice['variant_id'],
    );
    return '${product.name}${variants.isEmpty ? '' : ' / ${variants.first.name}'}';
  }

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.product.comboSlots.length; i++) {
      final choices = widget.product.comboSlots[i]['choices'] as List;
      if (choices.length == 1)
        components[i] = choices.first['product_id'] as int;
    }
  }

  CartItem selection() {
    var extra = 0;
    final labels = <String>[];
    for (final group in widget.product.modifierGroups) {
      for (final option in group['options'] as List) {
        if (modifiers.contains(option['id'])) {
          extra += cents(option['price_delta']);
          labels.add('${option['name']}');
        }
      }
    }
    for (var i = 0; i < widget.product.comboSlots.length; i++) {
      final slot = widget.product.comboSlots[i];
      final matches = (slot['choices'] as List).where(
        (c) => c['product_id'] == components[i],
      );
      if (matches.isNotEmpty) {
        extra += cents(matches.first['extra_price']);
        labels.add(
          '${slot['quantity']} × ${choiceName(Map<String, dynamic>.from(matches.first as Map))}',
        );
      }
    }
    return CartItem(
      product: widget.product,
      variant: variant,
      quantity: 1,
      modifierIds: modifiers.toList()..sort(),
      comboSelections: [
        for (var i = 0; i < widget.product.comboSlots.length; i++)
          components[i] ?? 0,
      ],
      extraCents: extra,
      configurationLabel: labels.join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.product.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            if (widget.product.hasVariants)
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Size'),
                isExpanded: true,
                items: widget.product.variants
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          '${v.name} · \$${v.price.toStringAsFixed(2)}',
                        ),
                      ),
                    )
                    .toList(),
                validator: (v) => v == null ? 'Choose a size' : null,
                onChanged: (id) => setState(
                  () => variant = widget.product.variants.firstWhere(
                    (v) => v.id == id,
                  ),
                ),
              ),
            for (var i = 0; i < widget.product.comboSlots.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownButtonFormField<int>(
                  initialValue: components[i],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText:
                        '${widget.product.comboSlots[i]['name']} × ${widget.product.comboSlots[i]['quantity']}',
                  ),
                  items: [
                    for (final c
                        in widget.product.comboSlots[i]['choices'] as List)
                      DropdownMenuItem(
                        value: c['product_id'] as int,
                        child: Text(
                          '${choiceName(Map<String, dynamic>.from(c as Map))} (+\$${(cents(c['extra_price']) / 100).toStringAsFixed(2)})',
                        ),
                      ),
                  ],
                  validator: (v) => v == null ? 'Choose an item' : null,
                  onChanged: (v) => setState(() => components[i] = v!),
                ),
              ),
            for (final group in widget.product.modifierGroups)
              FormField<int>(
                validator: (_) {
                  final count = (group['options'] as List)
                      .where((o) => modifiers.contains(o['id']))
                      .length;
                  final min = (group['min_select'] as num).toInt();
                  return count <
                              (group['is_required'] == true && min == 0
                                  ? 1
                                  : min) ||
                          count > (group['max_select'] as num).toInt()
                      ? 'Check the number of choices.'
                      : null;
                },
                builder: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '${group['name']} · ${group['min_select']}–${group['max_select']} choices${group['is_required'] == true ? ' · required' : ''}',
                    ),
                    for (final option in group['options'] as List)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${option['name']} (+\$${(cents(option['price_delta']) / 100).toStringAsFixed(2)})',
                        ),
                        value: modifiers.contains(option['id']),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            modifiers.add(option['id'] as int);
                          } else {
                            modifiers.remove(option['id']);
                          }
                        }),
                      ),
                    if (state.hasError)
                      Text(
                        state.errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate())
                  Navigator.of(context).pop(selection());
              },
              child: Text(
                'Add · \$${selection().unitPrice.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
