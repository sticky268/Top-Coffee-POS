import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../application/branch_list_controller.dart';
import '../application/branch_list_state.dart';
import '../domain/branch_models.dart';

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  final _searchController = TextEditingController();

  bool? _selectedActive;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() {
    return ref
        .read(branchListControllerProvider.notifier)
        .applySearch(_searchController.text);
  }

  Future<void> _refresh() {
    return ref.read(branchListControllerProvider.notifier).refresh();
  }

  Future<void> _setActive(bool? isActive) async {
    setState(() {
      _selectedActive = isActive;
    });

    await ref
        .read(branchListControllerProvider.notifier)
        .setActive(isActive);
  }

  Future<void> _clearFilters() async {
    _searchController.clear();

    setState(() {
      _selectedActive = null;
    });

    await ref
        .read(branchListControllerProvider.notifier)
        .clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    if (authState is! AuthAuthenticated) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final user = authState.user;

    if (!user.hasPermission('branches.manage')) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Branches'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to manage branches.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final state = ref.watch(branchListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches'),
        actions: [
          IconButton(
            onPressed: () async {
              final created = await context.push<bool>('/branches/add');

              if (created == true && mounted) {
                await ref
                    .read(branchListControllerProvider.notifier)
                    .refresh();
              }
            },
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Add branch',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearch(),
          _buildFilters(),
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search name, code, address or phone',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () async {
                    _searchController.clear();

                    await ref
                        .read(branchListControllerProvider.notifier)
                        .applySearch('');

                    if (mounted) {
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.clear),
                ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<bool?>(
              value: _selectedActive,
              hint: const Text('Status'),
              items: const [
                DropdownMenuItem<bool?>(
                  value: null,
                  child: Text('All status'),
                ),
                DropdownMenuItem<bool?>(
                  value: true,
                  child: Text('Active'),
                ),
                DropdownMenuItem<bool?>(
                  value: false,
                  child: Text('Inactive'),
                ),
              ],
              onChanged: _setActive,
            ),
          ),
          if (_selectedActive != null ||
              _searchController.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BranchListState state) {
    if (state is BranchListLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state is BranchListError) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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

    final loaded = state as BranchListLoaded;

    if (loaded.branches.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(
              Icons.account_tree_outlined,
              size: 64,
            ),
            SizedBox(height: 16),
            Center(
              child: Text('No branches found'),
            ),
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
            ref.read(branchListControllerProvider.notifier).loadMore();
          }

          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount:
              loaded.branches.length + (loaded.isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= loaded.branches.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final branch = loaded.branches[index];

            return _BranchCard(
              branch: branch,
              onTap: () async {
                final changed = await context.push<bool>(
                  '/branches/${branch.id}',
                );

                if (changed == true && mounted) {
                  await ref
                      .read(branchListControllerProvider.notifier)
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

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.onTap,
  });

  final Branch branch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: const CircleAvatar(
          child: Icon(Icons.account_tree_outlined),
        ),
        title: Text(
          branch.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                branch.code,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (branch.address != null &&
                  branch.address!.isNotEmpty)
                Text(
                  branch.address!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (branch.phone != null && branch.phone!.isNotEmpty)
                Text(
                  branch.phone!,
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
              '${branch.usersCount} ${branch.usersCount == 1 ? 'user' : 'users'}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              branch.isActive ? 'Active' : 'Inactive',
            ),
          ],
        ),
      ),
    );
  }
}
