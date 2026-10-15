import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/printer/print_queue_providers.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../settings/data/receipt_settings.dart';

/// Manual access records its reason without changing sales or cash totals.
class CashDrawerButton extends ConsumerStatefulWidget {
  const CashDrawerButton({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<CashDrawerButton> createState() => _CashDrawerButtonState();
}

class _CashDrawerButtonState extends ConsumerState<CashDrawerButton> {
  bool _busy = false;
  bool _prompting = false;

  bool _allowed() {
    final auth = ref.read(authControllerProvider);
    final branch = ref.read(currentBranchProvider);
    return auth is AuthAuthenticated &&
        branch != null &&
        auth.user.hasPermission('orders.create') &&
        (auth.user.hasPermission('branches.view-all') ||
            auth.user.branches.any((b) => b.id == branch.id));
  }

  Future<void> _open() async {
    if (_busy || _prompting || !_allowed()) return;
    final selected = ref.read(printScopeProvider);
    final branch = ref.read(currentBranchProvider);
    if (selected == null || branch == null) return;
    setState(() => _prompting = true);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _DrawerReasonDialog(),
    );
    if (!mounted) return;
    setState(() => _prompting = false);
    if (reason == null ||
        !_allowed() ||
        ref.read(printScopeProvider) != selected) {
      return;
    }
    final queue = ref.read(printQueueProvider);
    setState(() => _busy = true);
    var message = 'Drawer command sent. Check the drawer.';
    try {
      await queue.openCashDrawer(selected, () async {
        final settings = await ReceiptSettings.load(
            branchKey: branch.code, branchNameFallback: branch.name);
        if (!settings.printerEnabled) {
          throw StateError('Enable this branch’s printer in Receipt Settings.');
        }
        return settings.printerIpAddress;
      }, () {
        if (!mounted ||
            !_allowed() ||
            ref.read(printScopeProvider) != selected) {
          throw StateError(
              'Sign in and select the original branch before opening the drawer.');
        }
      }, reason: reason);
    } catch (error) {
      message =
          'Could not confirm drawer command. Check the drawer before retrying. $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || ref.read(printScopeProvider) != selected) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    ref.watch(currentBranchProvider);
    if (!_allowed()) return const SizedBox.shrink();
    if (widget.compact) {
      return pos_ui.IconButton(
        tooltip: 'Open cash drawer',
        onPressed: _busy || _prompting ? null : _open,
        isLoading: _busy,
        icon: const Icon(Icons.point_of_sale),
      );
    }
    return pos_ui.SecondaryButton.icon(
      onPressed: _busy || _prompting ? null : _open,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.point_of_sale),
      label: Text(_busy ? 'Sending…' : 'Open cash drawer'),
    );
  }
}

class _DrawerReasonDialog extends StatefulWidget {
  const _DrawerReasonDialog();
  @override
  State<_DrawerReasonDialog> createState() => _DrawerReasonDialogState();
}

class _DrawerReasonDialogState extends State<_DrawerReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_submitted) return;
    if (_form.currentState!.validate()) {
      _submitted = true;
      Navigator.of(context).pop(_reason.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Why are you opening the drawer?'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'The request is recorded with your name and branch. Opening the drawer does not change cash totals.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reason,
                  autofocus: true,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'For example, make change',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _confirm(),
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? 'Enter a reason with at least 3 characters.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(onPressed: _confirm, child: const Text('Open drawer')),
        ],
      );
}
