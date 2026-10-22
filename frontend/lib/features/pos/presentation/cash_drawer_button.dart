import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/printer/print_queue_providers.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../settings/data/receipt_settings.dart';

/// Manual access opens immediately without recording drawer activity.
class CashDrawerButton extends ConsumerStatefulWidget {
  const CashDrawerButton({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<CashDrawerButton> createState() => _CashDrawerButtonState();
}

class _CashDrawerButtonState extends ConsumerState<CashDrawerButton> {
  bool _busy = false;

  bool _allowed() {
    final auth = ref.read(authControllerProvider);
    final branch = ref.read(currentBranchProvider);
    return auth is AuthAuthenticated &&
        branch != null &&
        auth.user.hasPermission('orders.create') &&
        (!auth.user.requireManagerControls || auth.user.canApproveCheckout) &&
        (auth.user.hasPermission('branches.view-all') ||
            auth.user.branches.any((b) => b.id == branch.id));
  }

  Future<void> _open() async {
    if (_busy || !_allowed()) return;
    final selected = ref.read(printScopeProvider);
    final branch = ref.read(currentBranchProvider);
    if (selected == null || branch == null) return;
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
      }, recordActivity: false);
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
        boxed: true,
        tooltip: 'Open cash drawer',
        onPressed: _busy ? null : _open,
        isLoading: _busy,
        icon: const Icon(Icons.point_of_sale),
      );
    }
    return pos_ui.SecondaryButton.icon(
      onPressed: _busy ? null : _open,
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
