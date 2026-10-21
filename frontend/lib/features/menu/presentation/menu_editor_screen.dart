import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/menu_repository.dart';

class MenuEditorScreen extends ConsumerStatefulWidget {
  const MenuEditorScreen({
    super.key,
    required this.section,
    required this.catalog,
    this.initial,
  });
  final String section;
  final MenuRecord catalog;
  final MenuRecord? initial;
  @override
  ConsumerState<MenuEditorScreen> createState() => _MenuEditorState();
}

class _MenuEditorState extends ConsumerState<MenuEditorScreen> {
  final form = GlobalKey<FormState>();
  late final MenuRecord draft;
  bool saving = false;
  String? error;
  bool get combo => widget.section == 'Combos';
  bool get discount => widget.section == 'Discounts';
  List<MenuRecord> records(String key) => (widget.catalog[key] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<MenuRecord> get products => records(
    'products',
  ).where((p) => (p['combo_slots'] as List? ?? []).isEmpty).toList();

  @override
  void initState() {
    super.initState();
    draft = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.initial ?? {})) as Map,
    );
    draft.putIfAbsent('name', () => '');
    draft.putIfAbsent('is_active', () => true);
    if (combo) {
      draft.putIfAbsent('base_price', () => '0.00');
      draft.putIfAbsent('combo_slots', () => <dynamic>[]);
    } else if (discount) {
      draft.putIfAbsent('type', () => 'percent');
      draft.putIfAbsent('value', () => '10');
      draft.putIfAbsent('requires_manager', () => false);
      draft['all_branches'] =
          widget.initial != null && draft['branch_id'] == null;
    } else {
      draft.putIfAbsent('min_select', () => 0);
      draft.putIfAbsent('max_select', () => 1);
      draft.putIfAbsent('is_required', () => false);
      draft['product_ids'] = [
        for (final p in draft['products'] as List? ?? []) p['id'],
      ];
      final branch = ref.read(currentBranchProvider)?.id;
      draft['options'] = [
        for (final option in draft['modifiers'] as List? ?? [])
          {
            ...option as Map,
            'recipe': [
              for (final r in option['recipe_items'] as List? ?? [])
                if (r['branch_id'] == branch)
                  {
                    'ingredient_id': r['ingredient_id'],
                    'quantity_used': r['quantity_used'],
                  },
            ],
          },
      ];
    }
  }

  Widget text(
    String label,
    MenuRecord object,
    String key, {
    bool money = false,
    bool integer = false,
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: '${object[key] ?? ''}',
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: money || integer
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: (v) {
          if (optional && (v == null || v.trim().isEmpty)) return null;
          if (v == null || v.trim().isEmpty) return 'Required';
          if (integer && (int.tryParse(v) == null || int.parse(v) < 0))
            return 'Enter a whole number';
          if (money && !RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(v))
            return 'Enter a positive amount';
          return null;
        },
        onChanged: (v) => object[key] = integer
            ? int.tryParse(v) ?? 0
            : optional && v.isEmpty
            ? null
            : v.trim(),
      ),
    );
  }

  Widget select(
    String label,
    MenuRecord object,
    String key,
    List<MenuRecord> choices,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<int>(
      initialValue: choices.any((c) => c['id'] == object[key])
          ? object[key] as int?
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: choices
          .map(
            (c) => DropdownMenuItem(
              value: c['id'] as int,
              child: Text('${c['name']}', overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      validator: (v) => v == null ? 'Choose one' : null,
      onChanged: (v) => setState(() {
        object[key] = v;
        if (key == 'product_id') object['variant_id'] = null;
      }),
    ),
  );

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final branch = ref.read(currentBranchProvider)?.id;
    if (branch == null) return;
    if (combo && (draft['combo_slots'] as List).isEmpty ||
        !combo && !discount && (draft['options'] as List).isEmpty) {
      setState(
        () => error = combo
            ? 'Add at least one combo slot.'
            : 'Add at least one option.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(menuRepositoryProvider)
          .save(widget.section.toLowerCase(), branch, draft);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider);
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: PageAppBar(
          title: Text(
            '${widget.initial == null ? 'Add' : 'Edit'} ${combo
                ? 'combo'
                : discount
                ? 'discount'
                : 'modifier group'}',
          ),
        ),
        body: PageContent(
          maxWidth: 800,
          child: AbsorbPointer(
            absorbing: saving,
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    combo || discount
                        ? 'Branch: ${branch?.name ?? ''}'
                        : 'Group and prices are shared across the business. Ingredient usage below applies to ${branch?.name ?? 'this branch'}.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  text('Name', draft, 'name'),
                  if (combo) ...comboFields(),
                  if (discount) ...discountFields(),
                  if (!combo && !discount) ...modifierFields(),
                  if (combo || discount)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      subtitle: const Text(
                        'Archive to stop new sales while retaining history.',
                      ),
                      value: draft['is_active'] == true,
                      onChanged: (v) => setState(() => draft['is_active'] = v),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> discountFields() => [
    DropdownButtonFormField<String>(
      initialValue: draft['type'] as String,
      decoration: const InputDecoration(labelText: 'Discount type'),
      items: const [
        DropdownMenuItem(value: 'percent', child: Text('Percentage')),
        DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
      ],
      onChanged: (v) => setState(() => draft['type'] = v),
    ),
    const SizedBox(height: 16),
    text('Value', draft, 'value', money: true),
    text(
      'Starts on (YYYY-MM-DD, optional)',
      draft,
      'starts_on',
      optional: true,
    ),
    text('Ends on (YYYY-MM-DD, optional)', draft, 'ends_on', optional: true),
    const Text(
      'Dates use the branch timezone. Only one saved offer applies per order; it replaces the manual discount.',
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('All branches'),
      value: draft['all_branches'] == true,
      onChanged: (v) => setState(() => draft['all_branches'] = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Manager approval required'),
      value: draft['requires_manager'] == true,
      onChanged: (v) => setState(() => draft['requires_manager'] = v),
    ),
  ];

  List<Widget> comboFields() => [
    select('Category', draft, 'category_id', records('categories')),
    text('Combo base price', draft, 'base_price', money: true),
    const Text(
      'Add a slot for each included item. Multiple choices let the customer choose one. Slot quantity multiplies ingredient usage; extra price applies once per combo.',
    ),
    const SizedBox(height: 12),
    for (final slot in draft['combo_slots'] as List)
      Card(
        key: ObjectKey(slot),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text('Slot name', slot as MenuRecord, 'name'),
              text('Included quantity', slot, 'quantity', integer: true),
              for (final choice in slot['choices'] as List)
                Container(
                  key: ObjectKey(choice),
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      select(
                        'Item',
                        choice as MenuRecord,
                        'product_id',
                        products,
                      ),
                      if (choice['product_id'] != null)
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                            '${identityHashCode(choice)}:${choice['product_id']}',
                          ),
                          initialValue: choice['variant_id'] as int?,
                          decoration: const InputDecoration(labelText: 'Size'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text('Base size'),
                            ),
                            for (final v
                                in products.firstWhere(
                                      (p) => p['id'] == choice['product_id'],
                                    )['variants']
                                    as List)
                              if (v['is_active'] == true)
                                DropdownMenuItem(
                                  value: v['id'] as int,
                                  child: Text('${v['name']}'),
                                ),
                          ],
                          onChanged: (v) => choice['variant_id'] = v,
                        ),
                      const SizedBox(height: 12),
                      text('Extra charge', choice, 'extra_price', money: true),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => (slot['choices'] as List).remove(choice),
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Remove choice'),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(
                  () => (slot['choices'] as List).add(<String, dynamic>{
                    'extra_price': '0.00',
                  }),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add choice'),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => (draft['combo_slots'] as List).remove(slot)),
                child: const Text('Remove slot'),
              ),
            ],
          ),
        ),
      ),
    OutlinedButton.icon(
      onPressed: () => setState(
        () => (draft['combo_slots'] as List).add(<String, dynamic>{
          'name': '',
          'quantity': 1,
          'choices': <dynamic>[
            <String, dynamic>{'extra_price': '0.00'},
          ],
        }),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add included item slot'),
    ),
  ];

  List<Widget> modifierFields() => [
    text('Minimum selections', draft, 'min_select', integer: true),
    text('Maximum selections', draft, 'max_select', integer: true),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Required choice'),
      value: draft['is_required'] == true,
      onChanged: (v) => setState(() => draft['is_required'] = v),
    ),
    Text('Options', style: Theme.of(context).textTheme.titleMedium),
    for (final option in draft['options'] as List)
      Card(
        key: ObjectKey(option),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text('Option name', option as MenuRecord, 'name'),
              text('Extra price', option, 'price_delta', money: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active option'),
                value: option['is_active'] == true,
                onChanged: (v) => setState(() => option['is_active'] = v),
              ),
              for (final row in option['recipe'] as List)
                Column(
                  key: ObjectKey(row),
                  children: [
                    select(
                      'Ingredient',
                      row as MenuRecord,
                      'ingredient_id',
                      records('ingredients'),
                    ),
                    text(
                      'Quantity in ingredient stock units',
                      row,
                      'quantity_used',
                      money: true,
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => (option['recipe'] as List).remove(row),
                      ),
                      child: const Text('Remove ingredient'),
                    ),
                  ],
                ),
              TextButton.icon(
                onPressed: () => setState(
                  () => (option['recipe'] as List).add(<String, dynamic>{
                    'quantity_used': '1',
                  }),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient usage'),
              ),
            ],
          ),
        ),
      ),
    OutlinedButton.icon(
      onPressed: () => setState(
        () => (draft['options'] as List).add(<String, dynamic>{
          'name': '',
          'price_delta': '0.00',
          'is_active': true,
          'recipe': <dynamic>[],
        }),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add option'),
    ),
    const SizedBox(height: 20),
    Text('Assign to items', style: Theme.of(context).textTheme.titleMedium),
    const Text(
      'Assignments apply across branches where these items are sold. A group with no assignments stays available for future use.',
    ),
    for (final product in records('products'))
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${product['name']}'),
        value: (draft['product_ids'] as List).contains(product['id']),
        onChanged: (v) => setState(() {
          final ids = draft['product_ids'] as List;
          if (v == true) {
            ids.add(product['id']);
          } else {
            ids.remove(product['id']);
          }
        }),
      ),
  ];
}
