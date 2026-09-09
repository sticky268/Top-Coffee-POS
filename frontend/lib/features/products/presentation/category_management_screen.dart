import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../application/products_controller.dart';
import '../application/products_state.dart';
import '../data/products_repository.dart';

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

                            return ListTile(
                              leading: const Icon(Icons.category_outlined),
                              title: Text(category.name),
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