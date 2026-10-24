import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:go_router/go_router.dart';
import 'appearance_settings_card.dart';
import 'app_design_settings_card.dart';
import 'manager_pin_settings_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: const PageAppBar(title: Text('Settings')),
      body: PageContent(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Your workspace',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Personalize appearance, manage receipts, and review your account.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            const AppDesignSettingsCard(),
            const SizedBox(height: 16),
            const AppearanceSettingsCard(),
            const SizedBox(height: 16),
            Card(
                child: RecordTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: 'Home layout',
              subtitle: 'Classic, Modern, or colorful Coffee Counter',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/home-layout'),
            )),
            if (auth is AuthAuthenticated && auth.user.canApproveCheckout)
              ManagerPinSettingsCard(
                key: ValueKey(auth.user.id),
                userId: auth.user.id,
              ),
            const SizedBox(height: 16),
            Card(
              child: RecordTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: 'Receipt Settings',
                subtitle:
                    'Configure receipts, printer, logo, and receipt layout',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/receipt'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: RecordTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: 'Subscription',
                subtitle:
                    'View your plan, branch usage, and subscription status',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/subscription'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: RecordTile(
                leading: const Icon(Icons.info_outline),
                title: 'About',
                subtitle: 'App information',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/about'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
