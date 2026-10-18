import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cash_drawer_journal.dart';
import 'cash_drawer_providers.dart';

/// Audit review only. This screen has no printer or payment dependency.
class CashDrawerActivityScreen extends ConsumerWidget {
  const CashDrawerActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(cashDrawerScopeProvider);
    return Scaffold(
      appBar: PageAppBar(
        title: const Text('Drawer activity'),
        actions: [
          if (selected != null)
            IconButton(
              tooltip: 'Upload pending audit records',
              onPressed: () => unawaited(ref.read(cashDrawerSyncProvider).sync(force: true)),
              icon: const Icon(Icons.sync),
            ),
        ],
      ),
      body: selected == null
          ? const Center(child: Text('Sign in and select an authorized branch to view drawer activity.'))
          : ref.watch(cashDrawerActivityProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: TextButton(
                onPressed: () => ref.invalidate(cashDrawerActivityProvider),
                child: const Text('Could not load drawer activity. Try again.'),
              )),
              data: (items) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('This history records drawer commands and audit uploads. It cannot confirm physical opening. Retrying an audit upload never opens the drawer.'),
                        const SizedBox(height: 16),
                        if (items.isEmpty) const Text('No drawer requests for your account and this branch.'),
                      ],
                    );
                  }
                  return _DrawerActivityCard(
                    item: items[items.length - index], selected: selected,
                  );
                },
              ),
            ),
    );
  }
}

class _DrawerActivityCard extends ConsumerStatefulWidget {
  const _DrawerActivityCard({required this.item, required this.selected});
  final CashDrawerActivity item;
  final DrawerScope selected;
  @override
  ConsumerState<_DrawerActivityCard> createState() => _DrawerActivityCardState();
}

class _DrawerActivityCardState extends ConsumerState<_DrawerActivityCard> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy || ref.read(cashDrawerScopeProvider) != widget.selected) return;
    final journal = ref.read(cashDrawerJournalProvider);
    final sync = ref.read(cashDrawerSyncProvider);
    setState(() => _busy = true);
    try {
      await journal.retryUpload(widget.item.event.id, widget.selected);
      if (!mounted || ref.read(cashDrawerScopeProvider) != widget.selected) return;
      await sync.sync(force: true);
    } catch (_) {
      if (mounted && ref.read(cashDrawerScopeProvider) == widget.selected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not queue this audit upload. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final event = item.event;
    final command = switch (event.status) {
      'command_sent' => 'Command sent · physical opening unconfirmed',
      'unconfirmed' => 'Command unconfirmed · check the drawer',
      _ => 'Attempt recorded · outcome unknown',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.source == 'cash_sale' ? 'Cash sale #${event.orderId}' : 'Manual drawer request',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(event.reason),
            Text(command),
            Text('Device time: ${DateFormat.yMMMd().add_jm().format(event.requestedAt.toLocal())}'),
            const SizedBox(height: 8),
            Text(item.review != null ? 'Audit upload needs review'
                : item.uploaded ? 'Audit saved to server' : 'Waiting to upload audit'),
            if (item.review != null) ...[
              Text(item.review!.message),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _retry,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? 'Uploading audit…' : 'Retry audit upload'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
