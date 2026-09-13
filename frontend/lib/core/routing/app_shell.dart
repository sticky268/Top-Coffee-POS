import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/widgets/dashboard_navigation.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Top Coffee POS'),
            ),
            drawer: Drawer(
              child: DashboardNavigation(
                selectedRoute: location,
              ),
            ),
            body: child,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              DashboardNavigation(
                selectedRoute: location,
              ),
              Expanded(
                child: child,
              ),
            ],
          ),
        );
      },
    );
  }
}

