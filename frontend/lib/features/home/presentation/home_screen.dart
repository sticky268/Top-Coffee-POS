import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';

/// Temporary landing screen for authenticated users. Role-specific screens
/// (POS home, Kitchen Display, Manager dashboard) are built in later phases
/// (5, 11, 13) and will replace/route from here based on the user's role.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Coffee POS'),
        actions: [
          pos_ui.IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: user == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Welcome, ${user.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Roles: ${user.roles.join(', ')}'),
                  Text(
                    'Branches: ${user.branches.map((b) => b.name).join(', ')}',
                  ),
                ],
              ),
      ),
    );
  }
}
