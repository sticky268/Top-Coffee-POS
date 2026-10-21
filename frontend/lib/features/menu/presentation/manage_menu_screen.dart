import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../../../core/subscription/subscription_action_guard.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../products/domain/managed_product_models.dart';
import '../../pos/domain/pos_models.dart';
import '../../products/presentation/product_form_screen.dart';
import '../../products/presentation/category_management_screen.dart';
import 'branch_availability_dialog.dart';
import '../data/menu_repository.dart';
import '../../pos/application/pos_catalog_controller.dart';
import 'menu_editor_screen.dart';

class ManageMenuScreen extends ConsumerWidget {
  const ManageMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final allowed =
        auth is AuthAuthenticated && auth.user.hasPermission('products.manage');
    final branch = ref.watch(currentBranchProvider);
    return Scaffold(
      appBar: const PageAppBar(title: Text('Manage Menu')),
      body: PageContent(
        maxWidth: 1000,
        child: !allowed
            ? const Center(
                child: Text('You do not have permission to manage the menu.'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    branch?.name ?? 'Select a branch on the dashboard',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Build your menu, organise choices and control promotions.',
                  ),
                  const SizedBox(height: 20),
                  for (final section in const [
                    (
                      'Items',
                      'Prices, sizes, photos, recipes and availability',
                      Icons.local_cafe_outlined,
                    ),
                    (
                      'Combos',
                      'Bundles, included quantities and customer choices',
                      Icons.fastfood_outlined,
                    ),
                    (
                      'Categories',
                      'Menu groups and display order',
                      Icons.category_outlined,
                    ),
                    (
                      'Discounts',
                      'Fixed or percentage offers and schedules',
                      Icons.discount_outlined,
                    ),
                    (
                      'Modifiers',
                      'Milk, ice, sugar, toppings and extra ingredients',
                      Icons.tune,
                    ),
                  ])
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: Icon(
                          section.$3,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(section.$1),
                        subtitle: Text(section.$2),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: branch == null
                            ? null
                            : () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => section.$1 == 'Categories'
                                        ? const CategoryManagementScreen()
                                        : MenuSectionScreen(
                                            section: section.$1,
                                          ),
                                  ),
                                );
                                ref.invalidate(menuDataProvider);
                              },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class MenuSectionScreen extends ConsumerStatefulWidget {
  const MenuSectionScreen({super.key, required this.section});
  final String section;
  @override
  ConsumerState<MenuSectionScreen> createState() => _MenuSectionState();
}

class _MenuSectionState extends ConsumerState<MenuSectionScreen> {
  String search = '';
  bool archived = false;

  Future<void> edit(MenuRecord data, MenuRecord? record) async {
    if (widget.section == 'Items') {
      final categories = (data['categories'] as List)
          .map((e) => PosCategory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (categories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a category first.')),
        );
        return;
      }
      await context.push(
        '/products/form',
        extra: ProductFormArgs(
          categories: categories,
          initialProduct: record == null
              ? null
              : ManagedProduct.fromJson({
                  ...record,
                  'images': [
                    for (final image in record['images'] as List? ?? [])
                      {...image as Map, 'url': image['url']},
                  ],
                }),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MenuEditorScreen(
            section: widget.section,
            catalog: data,
            initial: record,
          ),
        ),
      );
    }
    ref.invalidate(menuDataProvider);
    ref.invalidate(posCatalogControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(menuDataProvider);
    final canModify = SubscriptionActionGuard.canModify(ref);
    return Scaffold(
      appBar: PageAppBar(title: Text(widget.section)),
      floatingActionButton: asyncData.hasValue && canModify
          ? FloatingActionButton.extended(
              onPressed: () => edit(asyncData.requireValue, null),
              icon: const Icon(Icons.add),
              label: Text(
                'Add ${widget.section == 'Categories' ? 'category' : widget.section == 'Items' ? 'item' : widget.section == 'Combos' ? 'combo' : widget.section == 'Discounts' ? 'discount' : 'modifier group'}',
              ),
            )
          : null,
      body: PageContent(
        maxWidth: 1000,
        child: asyncData.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the menu.'),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(menuError(error)),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(menuDataProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (data) {
            final source = data[
                widget.section == 'Items' || widget.section == 'Combos'
                    ? 'products'
                    : widget.section.toLowerCase()] as List;
            final rows = source
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where((row) {
              final combo = (row['combo_slots'] as List? ?? []).isNotEmpty;
              return (widget.section != 'Items' || !combo) &&
                  (widget.section != 'Combos' || combo) &&
                  (archived || row['is_active'] != false) &&
                  '${row['name']}'.toLowerCase().contains(
                        search.toLowerCase(),
                      );
            }).toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'Search ${widget.section.toLowerCase()}',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Include archived'),
                  value: archived,
                  onChanged: (v) => setState(() => archived = v),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(menuDataProvider);
                      await ref.read(menuDataProvider.future);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.isEmpty ? 1 : rows.length,
                      itemBuilder: (_, index) {
                        if (rows.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching entries. Add one to get started.',
                            ),
                          );
                        }
                        final row = rows[index];
                        return Card(
                          child: ListTile(
                            title: Text('${row['name']}'),
                            subtitle: Text(
                              row['is_active'] == false
                                  ? 'Archived · history retained'
                                  : widget.section == 'Discounts'
                                      ? '${row['type'] == 'percent' ? '${row['value']}%' : '\$${row['value']}'} · ${row['branch_id'] == null ? 'All branches' : 'This branch'}'
                                      : widget.section == 'Items' ||
                                              widget.section == 'Combos'
                                          ? 'Base price \$${row['base_price']} · tap to edit'
                                          : '${(row['modifiers'] as List? ?? []).length} options · shared across the business',
                            ),
                            trailing: widget.section == 'Items' ||
                                    widget.section == 'Combos'
                                ? PopupMenuButton<String>(
                                    enabled: canModify,
                                    tooltip: 'Item actions',
                                    onSelected: (action) async {
                                      if (action == 'edit') {
                                        await edit(data, row);
                                      }
                                      if (action == 'branch' &&
                                          context.mounted) {
                                        await showDialog<bool>(
                                            context: context,
                                            builder: (_) =>
                                                BranchAvailabilityDialog(
                                                    product: row));
                                        ref.invalidate(menuDataProvider);
                                        ref.invalidate(
                                            posCatalogControllerProvider);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit shared item')),
                                          PopupMenuItem(
                                              value: 'branch',
                                              child: Text(
                                                  'Branch pricing & availability'))
                                        ])
                                : const Icon(Icons.chevron_right),
                            onTap: canModify ? () => edit(data, row) : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
