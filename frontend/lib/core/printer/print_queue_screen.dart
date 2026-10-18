import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'print_queue.dart';
import 'print_queue_providers.dart';

class PrintQueueScreen extends ConsumerStatefulWidget {
  const PrintQueueScreen({super.key});
  @override
  ConsumerState<PrintQueueScreen> createState() => _PrintQueueScreenState();
}

class _PrintQueueScreenState extends ConsumerState<PrintQueueScreen> {
  bool _busy = false;
  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(PrintJob job) => job.paperConfirmed
      ? 'Printed — confirmed by cashier'
      : switch (job.status) {
          PrintStatus.waiting => 'Waiting',
          PrintStatus.sending => 'Sending',
          PrintStatus.sent => 'Sent — check paper',
          PrintStatus.failed => 'Failed before sending',
          PrintStatus.uncertain => 'Check paper — confirmation unknown',
          PrintStatus.cancelled => 'Cancelled',
        };
  Widget _card(PrintJob job, PrintScope scope) {
    final queue = ref.read(printQueueProvider);
    final disabled = _busy || job.status == PrintStatus.sending;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${job.isCopy ? 'COPY · ' : ''}${job.documentId.startsWith('bill:') ? 'Unpaid bill' : 'Receipt'} ${job.reference}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(_label(job)),
            if (job.payload['total'] != null)
              Text('Total: \$${job.payload['total']}'),
            if (job.payload['refunded'] != null &&
                job.payload['refunded'] != '0.00')
              Text(
                'Refunded: \$${job.payload['refunded']} · Net paid: \$${job.payload['netPaid']}',
              ),
            Text(DateFormat('MMM d, h:mm a').format(job.createdAt.toLocal())),
            if (job.printerIp != null) Text('Last printer: ${job.printerIp}'),
            Text('Attempts: ${job.attempts}'),
            if (job.error != null) Text(job.error!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (job.status == PrintStatus.waiting ||
                    job.status == PrintStatus.failed)
                  FilledButton.icon(
                    icon: const Icon(Icons.print_outlined),
                    label: Text(
                      job.status == PrintStatus.waiting ? 'Send' : 'Retry',
                    ),
                    onPressed: disabled
                        ? null
                        : () => _action(() async {
                            await queue.send(job.id, scope);
                          }),
                  ),
                if (job.status == PrintStatus.sent ||
                    job.status == PrintStatus.uncertain) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Reprint COPY'),
                    onPressed: disabled
                        ? null
                        : () => _action(() async {
                            if (!await _confirm(
                              'Print a COPY?',
                              'Check the paper first. The previous attempt may already have printed. This sends the saved document with a COPY label.',
                            )) {
                              return;
                            }
                            final copy = await queue.copy(job.id, scope);
                            await queue.send(copy.id, scope);
                          }),
                  ),
                  if (!job.paperConfirmed)
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => _action(() async {
                              if (await _confirm(
                                'Confirm paper output?',
                                'Only confirm after inspecting a readable, complete paper document.',
                              )) {
                                await queue.confirmPaper(job.id, scope);
                              }
                            }),
                      child: const Text('Confirm printed'),
                    ),
                ],
                if (job.status == PrintStatus.waiting ||
                    job.status == PrintStatus.failed ||
                    job.status == PrintStatus.uncertain)
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => _action(() async {
                            if (await _confirm(
                              'Cancel print job?',
                              'This only cancels the print job. It does not cancel or refund the sale.',
                            )) {
                              await queue.cancel(job.id, scope);
                            }
                          }),
                    child: const Text('Cancel job'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(printScopeProvider);
    final jobs = ref.watch(printJobsProvider);
    return Scaffold(
      appBar: PageAppBar(
        title: const Text('Print Queue'),
        actions: [
          IconButton(
            tooltip: 'Receipt Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings/receipt'),
          ),
        ],
      ),
      body: scope == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Select a branch and sign in with receipt access to view its print jobs.',
                ),
              ),
            )
          : jobs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not read print jobs: $error'),
                ),
              ),
              data: (values) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Jobs are saved on this device for your account and selected branch. Sent means accepted by the printer; check the paper before making a COPY.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${values.where((job) => job.status == PrintStatus.failed).length} failed · '
                    '${values.where((job) => job.status == PrintStatus.uncertain).length} need paper check · '
                    '${values.where((job) => job.status == PrintStatus.waiting).length} waiting',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (values.isEmpty)
                    const Text('No print jobs for this branch yet.'),
                  for (final job in values) _card(job, scope),
                ],
              ),
            ),
    );
  }
}
