import 'package:flutter/material.dart';

import '../../domain/managed_product_models.dart';

/// Shows a dialog to add ([initial] == null) or edit ([initial] != null)
/// a single variant. Returns the resulting variant, or null if cancelled.
/// This is local, unsaved form state — nothing is sent to the backend
/// until the parent Add/Edit Product form itself is submitted.
Future<ManagedProductVariant?> showVariantEditorDialog(
  BuildContext context, {
  ManagedProductVariant? initial,
}) {
  return showDialog<ManagedProductVariant>(
    context: context,
    builder: (context) => _VariantEditorDialog(initial: initial),
  );
}

class _VariantEditorDialog extends StatefulWidget {
  const _VariantEditorDialog({this.initial});

  final ManagedProductVariant? initial;

  @override
  State<_VariantEditorDialog> createState() => _VariantEditorDialogState();
}

class _VariantEditorDialogState extends State<_VariantEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _priceDeltaController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _skuController = TextEditingController(text: initial?.sku ?? '');
    _priceDeltaController = TextEditingController(
      text: initial != null ? initial.priceDelta.toStringAsFixed(2) : '0.00',
    );
    _isActive = initial?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _priceDeltaController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final skuText = _skuController.text.trim();
    final base = widget.initial ?? const ManagedProductVariant(name: '', priceDelta: 0);

    final result = base.copyWith(
      name: _nameController.text.trim(),
      sku: skuText.isEmpty ? null : skuText,
      clearSku: skuText.isEmpty,
      priceDelta: double.parse(_priceDeltaController.text.trim()),
      isActive: _isActive,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Variant' : 'Edit Variant'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skuController,
              decoration: const InputDecoration(labelText: 'SKU (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceDeltaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Price adjustment',
                helperText: 'Added to the base price — e.g. 0.50 or -0.25',
              ),
              validator: (value) =>
                  double.tryParse((value ?? '').trim()) == null ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
