import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Receipt Settings'),
              subtitle: const Text(
                'Configure receipts, printer, logo, and receipt layout',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/receipt'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Subscription'),
              subtitle: const Text(
                'View your plan, branch usage, and subscription status',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/subscription'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('App information'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ),
        ],
      ),
    );
  }
}
