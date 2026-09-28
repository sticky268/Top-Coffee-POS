import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../application/products_controller.dart';
import '../application/products_state.dart';
import '../data/products_repository.dart';
import '../../pos/domain/pos_models.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createCategory() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category name')),
      );
      return;
    }

    final branch = ref.read(currentBranchProvider);

    if (branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No branch is selected')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ref.read(productsRepositoryProvider).createCategory(
            branchId: branch.id,
            name: name,
          );

      if (!mounted) return;

      _nameController.clear();

      await ref.read(productsControllerProvider.notifier).refresh();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" created')),
      );
    } catch (e) {
      if (!mounted) return;

      final message =
          e is ApiException ? e.message : 'Could not create category';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _editCategory(PosCategory category) async {
    final nameController = TextEditingController(text: category.name);
    final sortOrderController = TextEditingController(
      text: category.sortOrder.toString(),
    );

    try {
      final result = await showDialog<_CategoryEditResult>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Edit Category'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Category name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sortOrderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    helperText: 'Lower numbers appear first',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final sortOrder =
                      int.tryParse(sortOrderController.text.trim());

                  if (name.isEmpty || sortOrder == null || sortOrder < 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a valid name and sort order (0 or higher)',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    _CategoryEditResult(
                      name: name,
                      sortOrder: sortOrder,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (result == null || !mounted) return;

      setState(() => _isSaving = true);

      try {
        await ref.read(productsRepositoryProvider).updateCategory(
              categoryId: category.id,
              name: result.name,
              sortOrder: result.sortOrder,
            );

        if (!mounted) return;

        await ref.read(productsControllerProvider.notifier).refresh();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${result.name}" updated')),
        );
      } catch (e) {
        if (!mounted) return;

        final message =
            e is ApiException ? e.message : 'Could not update category';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    } finally {
      nameController.dispose();
      sortOrderController.dispose();
    }
  }

  Future<void> _deactivateCategory(PosCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Deactivate Category?'),
          content: Text(
            'Are you sure you want to deactivate "${category.name}"? '
            'It will no longer appear in the active category list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Deactivate'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(productsRepositoryProvider).deleteCategory(
            categoryId: category.id,
          );

      if (!mounted) return;

      await ref.read(productsControllerProvider.notifier).refresh();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${category.name}" deactivated')),
      );
    } catch (e) {
      if (!mounted) return;

      final message =
          e is ApiException ? e.message : 'Could not deactivate category';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);
    final branch = ref.watch(currentBranchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (branch != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Branch: ${branch.name}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createCategory(),
                      decoration: const InputDecoration(
                        labelText: 'Category name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSaving ? null : _createCategory,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: switch (state) {
                  ProductsLoading() => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ProductsError(:final message) => Center(
                      child: Text(message),
                    ),
                  ProductsLoaded(:final categories) => categories.isEmpty
                      ? const Center(
                          child: Text('No categories yet'),
                        )
                      : ListView.separated(
                          itemCount: categories.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final isGlobal = category.branchId == null;

                            return ListTile(
                              leading: const Icon(Icons.category_outlined),
                              title: Text(category.name),
                              subtitle: Text(
                                'Sort order: ${category.sortOrder}'
                                '${isGlobal ? ' • Global' : ''}',
                              ),
                              trailing: isGlobal
                                  ? const Chip(
                                      label: Text('Global'),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          onPressed: _isSaving
                                              ? null
                                              : () => _editCategory(category),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          tooltip: 'Deactivate',
                                          onPressed: _isSaving
                                              ? null
                                              : () =>
                                                  _deactivateCategory(category),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryEditResult {
  const _CategoryEditResult({
    required this.name,
    required this.sortOrder,
  });

  final String name;
  final int sortOrder;
}