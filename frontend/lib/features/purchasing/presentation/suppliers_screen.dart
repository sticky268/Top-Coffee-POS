import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/domain/auth_models.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../application/supplier_list_controller.dart';
import '../application/supplier_list_state.dart';
import '../data/supplier_repository.dart';
import '../domain/purchase_models.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _searchController = TextEditingController();

  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    return ref.read(supplierListControllerProvider.notifier).refresh();
  }

  Future<void> _openSupplierForm({
    PurchaseSupplier? supplier,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(
        supplier: supplier,
      ),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _deleteSupplier(PurchaseSupplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete supplier?'),
          content: Text(
            'This will delete "${supplier.name}". This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(purchaseSupplierRepositoryProvider)
          .deleteSupplier(supplier.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier deleted successfully.'),
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(supplierListControllerProvider);

    final authState = ref.watch(authControllerProvider);
    final canManage = authState is AuthAuthenticated &&
        authState.user.hasPermission('inventory.manage');

    final filteredSuppliers = state is SupplierListLoaded
        ? state.suppliers.where((supplier) {
            final query = _search.trim().toLowerCase();

            if (query.isEmpty) return true;

            return supplier.name.toLowerCase().contains(query) ||
                (supplier.contactName?.toLowerCase().contains(query) ??
                    false) ||
                (supplier.phone?.toLowerCase().contains(query) ?? false) ||
                (supplier.email?.toLowerCase().contains(query) ?? false);
          }).toList()
        : const <PurchaseSupplier>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (canManage)
            IconButton(
              onPressed: () => _openSupplierForm(),
              icon: const Icon(Icons.add),
              tooltip: 'Add supplier',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _search = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search suppliers',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(
              state,
              filteredSuppliers,
              canManage,
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openSupplierForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Supplier'),
            )
          : null,
    );
  }

  Widget _buildBody(
    SupplierListState state,
    List<PurchaseSupplier> suppliers,
    bool canManage,
  ) {
    if (state is SupplierListLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state is SupplierListError) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (suppliers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            const Icon(
              Icons.local_shipping_outlined,
              size: 64,
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _search.trim().isEmpty
                    ? 'No suppliers found'
                    : 'No suppliers match your search',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: suppliers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final supplier = suppliers[index];

          return _SupplierCard(
            supplier: supplier,
            canManage: canManage,
            onEdit: () => _openSupplierForm(
              supplier: supplier,
            ),
            onDelete: () => _deleteSupplier(supplier),
          );
        },
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final PurchaseSupplier supplier;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final contact = supplier.contactName?.trim();
    final phone = supplier.phone?.trim();
    final email = supplier.email?.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Text(
                supplier.name.isEmpty
                    ? '?'
                    : supplier.name.substring(0, 1).toUpperCase(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (contact != null && contact.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (phone != null && phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (email != null && email.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _BranchLabel(
                    supplier: supplier,
                  ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchLabel extends ConsumerWidget {
  const _BranchLabel({
    required this.supplier,
  });

  final PurchaseSupplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (supplier.branchId == null) {
      return const Chip(
        avatar: Icon(Icons.public, size: 16),
        label: Text('Global'),
      );
    }

    final authState = ref.watch(authControllerProvider);

    if (authState is AuthAuthenticated) {
      for (final branch in authState.user.branches) {
        if (branch.id == supplier.branchId) {
          return Chip(
            avatar: const Icon(Icons.store_outlined, size: 16),
            label: Text(branch.name),
          );
        }
      }
    }

    final currentBranch = ref.watch(currentBranchProvider);

    return Chip(
      avatar: const Icon(Icons.store_outlined, size: 16),
      label: Text(
        currentBranch?.name ?? 'Branch ${supplier.branchId}',
      ),
    );
  }
}

class _SupplierFormDialog extends ConsumerStatefulWidget {
  const _SupplierFormDialog({
    this.supplier,
  });

  final PurchaseSupplier? supplier;

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState
    extends ConsumerState<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;

  int? _branchId;
  bool _saving = false;

  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();

    final supplier = widget.supplier;

    _nameController = TextEditingController(
      text: supplier?.name ?? '',
    );
    _contactController = TextEditingController(
      text: supplier?.contactName ?? '',
    );
    _phoneController = TextEditingController(
      text: supplier?.phone ?? '',
    );
    _emailController = TextEditingController(
      text: supplier?.email ?? '',
    );

    _branchId = supplier?.branchId ??
        ref.read(currentBranchProvider)?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  List<BranchSummary> get _branches {
    final authState = ref.read(authControllerProvider);

    if (authState is! AuthAuthenticated) {
      return const [];
    }

    return authState.user.branches;
  }

  bool get _canManageAllBranches {
    final authState = ref.read(authControllerProvider);

    return authState is AuthAuthenticated &&
        authState.user.hasPermission('branches.view-all');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (_branchId == null && !_canManageAllBranches) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a branch before saving the supplier.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final repository = ref.read(
        purchaseSupplierRepositoryProvider,
      );

      if (_isEditing) {
        await repository.updateSupplier(
          id: widget.supplier!.id,
          branchId: _branchId,
          name: name,
          contactName: contact.isEmpty ? null : contact,
          phone: phone.isEmpty ? null : phone,
          email: email.isEmpty ? null : email,
        );
      } else {
        await repository.createSupplier(
          branchId: _branchId,
          name: name,
          contactName: contact.isEmpty ? null : contact,
          phone: phone.isEmpty ? null : phone,
          email: email.isEmpty ? null : email,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = _branches;
    final canManageAllBranches = _canManageAllBranches;

    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit Supplier' : 'Add Supplier',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Supplier name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Supplier name is required.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _contactController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Contact name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';

                    if (email.isEmpty) {
                      return null;
                    }

                    if (!email.contains('@')) {
                      return 'Enter a valid email address.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                if (canManageAllBranches)
                  DropdownButtonFormField<int?>(
                    initialValue: _branchId,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Global'),
                      ),
                      ...branches.map(
                        (branch) => DropdownMenuItem<int?>(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              _branchId = value;
                            });
                          },
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      branches
                              .where(
                                (branch) => branch.id == _branchId,
                              )
                              .map((branch) => branch.name)
                              .firstOrNull ??
                          'Current branch',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text(_isEditing ? 'Save Changes' : 'Create'),
        ),
      ],
    );
  }
}
