import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/pos/data/pos_repository.dart';

import '../../features/dashboard/presentation/widgets/dashboard_navigation.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.selectedRoute});

  final Widget child;
  final String selectedRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usingCache = ref.watch(cachedCatalogProvider);
    final content = Column(children: [
      if (usingCache)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Text(
              'Using saved catalog. Orders will wait for server confirmation if the connection is unavailable.'),
        ),
      Expanded(child: child),
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop) {
          return Scaffold(
            appBar: AppBar(title: const Text('Top Coffee POS')),
            drawer: Drawer(
              child: DashboardNavigation(selectedRoute: selectedRoute),
            ),
            body: content,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              DashboardNavigation(selectedRoute: selectedRoute),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}
