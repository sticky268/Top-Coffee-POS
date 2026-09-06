import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../pos/domain/pos_models.dart';
import '../application/product_form_controller.dart';
import '../application/product_form_state.dart';
import '../application/products_controller.dart';
import '../domain/managed_product_models.dart';
import 'widgets/variant_editor_dialog.dart';

/// Bundled navigation arguments — passed via go_router's `extra`. The
/// category list is already loaded by ProductsController by the time this
/// screen is reached (from the Products list), so it's passed along
/// rather than re-fetched — reusing existing category data, per the
/// task's explicit instruction, rather than adding a second load.
class ProductFormArgs {
  const ProductFormArgs({required this.categories, this.initialProduct});

  final List<PosCategory> categories;

  /// null = Add Product mode. Non-null = Edit Product mode.
  final ManagedProduct? initialProduct;
}

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, required this.args});

  final ProductFormArgs args;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _basePriceController;

  int? _selectedCategoryId;
  bool _isActive = true;
  late List<ManagedProductVariant> _variants;

  bool get _isEditing => widget.args.initialProduct != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.args.initialProduct;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _skuController = TextEditingController(text: initial?.sku ?? '');
    _descriptionController = TextEditingController(text: initial?.description ?? '');
    _basePriceController = TextEditingController(
      text: initial != null ? initial.basePrice.toStringAsFixed(2) : '',
    );
    _selectedCategoryId = initial?.categoryId;
    _isActive = initial?.isActive ?? true;
    _variants = List.of(initial?.variants ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descriptionController.dispose();
    _basePriceController.dispose();
    super.dispose();
  }

  void _submit() {
    if (ref.read(productFormControllerProvider) is ProductFormSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a category')),
      );
      return;
    }

    final product = ManagedProduct(
      id: widget.args.initialProduct?.id,
      name: _nameController.text.trim(),
      sku: _skuController.text,
      description: _descriptionController.text,
      categoryId: _selectedCategoryId!,
      basePrice: double.parse(_basePriceController.text.trim()),
      isActive: _isActive,
      variants: _variants,
    );

    if (_isEditing) {
      // Editing never touches branch assignment — see
      // ProductsRepository.updateProduct()'s docblock for why: silently
      // reassigning an existing product's branches on every edit would be
      // a separate, unrelated behavior change.
      ref.read(productFormControllerProvider.notifier).update(product.id!, product);
    } else {
      // Without at least one branch assigned, a newly created product
      // gets zero branch_product rows and becomes permanently invisible
      // to GET /api/v1/products (it requires a matching branch for the
      // resolved user — see ProductController::index()). There is no
      // branch-selection UI in this milestone, so this uses the existing
      // AuthenticatedUser.branches data already loaded by auth, rather
      // than building new branch infrastructure. Defaults to the user's
      // first branch — correct for every current seeded account (each has
      // exactly one) and a known, deliberate simplification for a
      // genuinely multi-branch user until branch management exists as its
      // own feature.
      final authState = ref.read(authControllerProvider);
      final branchIds = authState is AuthAuthenticated && authState.user.branches.isNotEmpty
          ? [authState.user.branches.first.id]
          : const <int>[];

      ref.read(productFormControllerProvider.notifier).create(product, branchIds: branchIds);
    }
  }

  Future<void> _addVariant() async {
    final result = await showVariantEditorDialog(context);
    if (result != null && mounted) {
      setState(() => _variants = [..._variants, result]);
    }
  }

  Future<void> _editVariant(ManagedProductVariant variant) async {
    final result = await showVariantEditorDialog(context, initial: variant);
    if (result != null && mounted) {
      setState(() {
        _variants = [
          for (final v in _variants) if (v.formKey == variant.formKey) result else v,
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(productFormControllerProvider);
    final isSaving = formState is ProductFormSaving;
    final errorMessage = formState is ProductFormError ? formState.message : null;
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(symbol: '\$');

    ref.listen<ProductFormState>(productFormControllerProvider, (previous, next) {
      if (next is ProductFormSuccess && previous is! ProductFormSuccess) {
        // Refreshes the same, still-alive ProductsController instance
        // underneath this pushed route — not a new fetch mechanism.
        ref.read(productsControllerProvider.notifier).refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Product updated' : 'Product created')),
        );
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (errorMessage != null) ...[
                _ErrorBanner(message: errorMessage),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Product name', border: OutlineInputBorder()),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter a product name' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _skuController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'SKU (optional)', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                enabled: !isSaving,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _basePriceController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Base price',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null) return 'Enter a valid price';
                  if (parsed < 0) return 'Price cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: [
                  for (final category in widget.args.categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: isSaving ? null : (value) => setState(() => _selectedCategoryId = value),
                validator: (value) => value == null ? 'Select a category' : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Visible in the catalog when on'),
                value: _isActive,
                onChanged: isSaving ? null : (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Variants', style: theme.textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: isSaving ? null : _addVariant,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Variant'),
                  ),
                ],
              ),
              if (_variants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No variants — this product has a single price',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final variant in _variants)
                        ListTile(
                          title: Text(variant.name),
                          subtitle: variant.isActive ? null : const Text('Disabled'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${variant.priceDelta >= 0 ? '+' : ''}${currency.format(variant.priceDelta)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit variant',
                                onPressed: isSaving ? null : () => _editVariant(variant),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isSaving ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Create Product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
