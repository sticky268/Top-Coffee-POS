import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
              'Manage receipts and review your account.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
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
