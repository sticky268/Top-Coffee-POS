import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/subscription/subscription_action_guard.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../application/staff_list_controller.dart';
import '../application/staff_list_state.dart';
import '../domain/staff_models.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  final _searchController = TextEditingController();

  String? _selectedRole;
  int? _selectedBranchId;
  bool? _selectedActive;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() {
    return ref
        .read(staffListControllerProvider.notifier)
        .applySearch(_searchController.text);
  }

  Future<void> _refresh() {
    return ref.read(staffListControllerProvider.notifier).refresh();
  }

  Future<void> _setRole(String? role) async {
    setState(() {
      _selectedRole = role;
    });

    await ref.read(staffListControllerProvider.notifier).setRole(role);
  }

  Future<void> _setBranch(int? branchId) async {
    setState(() {
      _selectedBranchId = branchId;
    });

    await ref.read(staffListControllerProvider.notifier).setBranch(branchId);
  }

  Future<void> _setActive(bool? isActive) async {
    setState(() {
      _selectedActive = isActive;
    });

    await ref.read(staffListControllerProvider.notifier).setActive(isActive);
  }

  Future<void> _clearFilters() async {
    _searchController.clear();

    setState(() {
      _selectedRole = null;
      _selectedBranchId = null;
      _selectedActive = null;
    });

    await ref.read(staffListControllerProvider.notifier).clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = authState.user;

    if (!user.hasPermission('users.manage')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff & Permissions')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to manage staff.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final canModify = SubscriptionActionGuard.canModify(ref);
    final state = ref.watch(staffListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Permissions'),
        actions: [
          pos_ui.IconButton(
            onPressed: canModify
                ? () async {
                    final created = await context.push<bool>('/staff/add');

                    if (created == true && mounted) {
                      await ref
                          .read(staffListControllerProvider.notifier)
                          .refresh();
                    }
                  }
                : null,
            icon: const Icon(Icons.person_add_outlined),
            tooltip: canModify ? 'Add staff' : 'Subscription is read-only',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearch(),
          _buildFilters(user),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search name, phone or email',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : pos_ui.IconButton(
                  onPressed: () async {
                    _searchController.clear();

                    await ref
                        .read(staffListControllerProvider.notifier)
                        .applySearch('');

                    if (mounted) {
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.clear),
                ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        onChanged: (_) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildFilters(dynamic user) {
    final branches = user.branches;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedRole,
              hint: const Text('Role'),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All roles'),
                ),
                DropdownMenuItem<String?>(value: 'admin', child: Text('Admin')),
                DropdownMenuItem<String?>(
                  value: 'manager',
                  child: Text('Manager'),
                ),
                DropdownMenuItem<String?>(
                  value: 'cashier',
                  child: Text('Cashier'),
                ),
                DropdownMenuItem<String?>(
                  value: 'kitchen_staff',
                  child: Text('Kitchen Staff'),
                ),
              ],
              onChanged: _setRole,
            ),
          ),
          const SizedBox(width: 16),
          DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: _selectedBranchId,
              hint: const Text('Branch'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All branches'),
                ),
                ...branches.map(
                  (branch) => DropdownMenuItem<int?>(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                ),
              ],
              onChanged: _setBranch,
            ),
          ),
          const SizedBox(width: 16),
          DropdownButtonHideUnderline(
            child: DropdownButton<bool?>(
              value: _selectedActive,
              hint: const Text('Status'),
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('All status')),
                DropdownMenuItem<bool?>(value: true, child: Text('Active')),
                DropdownMenuItem<bool?>(value: false, child: Text('Inactive')),
              ],
              onChanged: _setActive,
            ),
          ),
          if (_selectedRole != null ||
              _selectedBranchId != null ||
              _selectedActive != null ||
              _searchController.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            pos_ui.SecondaryButton(
              onPressed: _clearFilters,
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(StaffListState state) {
    if (state is StaffListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is StaffListError) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(state.message, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      );
    }

    final loaded = state as StaffListLoaded;

    if (loaded.staff.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(Icons.people_outline, size: 64),
            SizedBox(height: 16),
            Center(child: Text('No staff found')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 300) {
            ref.read(staffListControllerProvider.notifier).loadMore();
          }

          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: loaded.staff.length + (loaded.isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index >= loaded.staff.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final staff = loaded.staff[index];

            return _StaffCard(
              staff: staff,
              onTap: () async {
                final changed = await context.push<bool>('/staff/${staff.id}');

                if (changed == true && mounted) {
                  await ref
                      .read(staffListControllerProvider.notifier)
                      .refresh();
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff, required this.onTap});

  final StaffMember staff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryBranch = staff.primaryBranch;

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Text(
            staff.name.isEmpty ? '?' : staff.name.substring(0, 1).toUpperCase(),
          ),
        ),
        title: Text(staff.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(staff.email, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (primaryBranch != null)
                Text(
                  '${primaryBranch.name} � ${primaryBranch.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _roleLabel(staff.primaryRole),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(staff.isActive ? 'Active' : 'Inactive'),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'kitchen_staff':
        return 'Kitchen Staff';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      case 'cashier':
        return 'Cashier';
      default:
        return role.isEmpty ? 'No role' : role;
    }
  }
}
