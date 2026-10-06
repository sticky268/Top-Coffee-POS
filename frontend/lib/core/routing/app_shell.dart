import 'package:flutter/material.dart';

import '../../features/dashboard/presentation/widgets/dashboard_navigation.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.selectedRoute});

  final Widget child;
  final String selectedRoute;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop) {
          return Scaffold(
            appBar: AppBar(title: const Text('Top Coffee POS')),
            drawer: Drawer(
              child: DashboardNavigation(selectedRoute: selectedRoute),
            ),
            body: child,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              DashboardNavigation(selectedRoute: selectedRoute),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}
