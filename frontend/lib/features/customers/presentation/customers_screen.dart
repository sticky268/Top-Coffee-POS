import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/customers_list_controller.dart';
import '../application/customers_list_state.dart';
import '../domain/customer_models.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() {
    return ref
        .read(customersListControllerProvider.notifier)
        .applySearch(_searchController.text);
  }

  Future<void> _refresh() {
    return ref.read(customersListControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customersListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            onPressed: () async {
              final created = await context.push<bool>('/customers/add');

              if (created == true && mounted) {
                await ref
                    .read(customersListControllerProvider.notifier)
                    .refresh();
              }
            },
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add customer',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search name, phone or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(
                                customersListControllerProvider.notifier,
                              )
                              .clearSearch();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(CustomersListState state) {
    if (state is CustomersListLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state is CustomersListError) {
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

    final loaded = state as CustomersListLoaded;

    if (loaded.customers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(
              Icons.people_outline,
              size: 64,
            ),
            SizedBox(height: 16),
            Center(
              child: Text('No customers found'),
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
            ref.read(customersListControllerProvider.notifier).loadMore();
          }

          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: loaded.customers.length + (loaded.isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= loaded.customers.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            return _CustomerCard(
              customer: loaded.customers[index],
              onTap: () async {
                final changed = await context.push<bool>(
                  '/customers/${loaded.customers[index].id}',
                );

                if (changed == true && mounted) {
                  await ref
                      .read(customersListControllerProvider.notifier)
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

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onTap,
  });

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(
            customer.name.isEmpty
                ? '?'
                : customer.name.substring(0, 1).toUpperCase(),
          ),
        ),
        title: Text(
          customer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          customer.phone?.isNotEmpty == true
              ? customer.phone!
              : customer.email ?? 'No contact information',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${customer.completedOrdersCount} orders'),
            const SizedBox(height: 4),
            Text(
              '\$${customer.completedOrdersTotal.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }
}
