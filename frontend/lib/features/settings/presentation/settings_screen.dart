import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/coffee_studio_theme.dart';

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
    if (CoffeeStudioTheme.active(context)) {
      void panel(String title, Widget content) {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                  appBar: PageAppBar(title: Text(title)),
                  body: PageContent(
                      maxWidth: 840,
                      child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [content])),
                )));
      }

      Widget tile(String title, String subtitle, IconData icon, int index,
              VoidCallback onTap) =>
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color:
                              CoffeeStudioTheme.accentSurface(context, index),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon)),
                  title: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onTap,
                ),
              ));
      return Scaffold(
        appBar: const PageAppBar(title: Text('Settings')),
        body: PageContent(
            maxWidth: 1040,
            child: ListView(padding: const EdgeInsets.all(28), children: [
              Text('Settings',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('Manage your workspace and preferences.'),
              const SizedBox(height: 28),
              tile(
                  'App theme',
                  'Original or Coffee Studio',
                  Icons.palette_outlined,
                  1,
                  () => panel('App theme', const AppDesignSettingsCard())),
              tile(
                  'Appearance',
                  'Light, dark, or device setting',
                  Icons.light_mode_outlined,
                  2,
                  () => panel('Appearance', const AppearanceSettingsCard())),
              tile(
                  'Receipt Settings',
                  'Receipt preview, font, paper and printer',
                  Icons.receipt_long_outlined,
                  0,
                  () => context.push('/settings/receipt')),
              if (auth is AuthAuthenticated && auth.user.canApproveCheckout)
                tile(
                    'Manager PIN',
                    'Manage checkout approval credentials',
                    Icons.lock_outline,
                    1,
                    () => panel(
                        'Manager PIN',
                        ManagerPinSettingsCard(
                            key: ValueKey(auth.user.id),
                            userId: auth.user.id))),
              tile(
                  'Subscription',
                  'Plan details and usage',
                  Icons.workspace_premium_outlined,
                  3,
                  () => context.push('/settings/subscription')),
              tile('About', 'App information', Icons.info_outline, 2,
                  () => context.push('/settings/about')),
            ])),
      );
    }
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
