import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/kitchen_settings_repository.dart';

class KitchenSettingsScreen extends ConsumerStatefulWidget {
  const KitchenSettingsScreen({super.key});

  @override
  ConsumerState<KitchenSettingsScreen> createState() => _KitchenSettingsScreenState();
}

class _KitchenSettingsScreenState extends ConsumerState<KitchenSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final branch = ref.read(currentBranchProvider);
    if (branch == null) {
      setState(() {
        _loading = false;
        _error = 'Select a branch first.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final enabled = await ref
          .read(kitchenSettingsRepositoryProvider)
          .load(branchId: branch.id);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final branch = ref.read(currentBranchProvider);
    if (branch == null || _saving) return;

    setState(() => _saving = true);
    try {
      final enabled = await ref
          .read(kitchenSettingsRepositoryProvider)
          .update(branchId: branch.id, useKitchenDisplay: _enabled);

      ref
          .read(currentBranchProvider.notifier)
          .selectBranch(branch.copyWith(useKitchenDisplay: enabled));

      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Kitchen Display enabled for undefined.'
                : 'Kitchen Display disabled for undefined.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save kitchen settings: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider);
    final auth = ref.watch(authControllerProvider);
    final canManage = auth is AuthAuthenticated &&
        auth.user.hasPermission('settings.manage');

    ref.listen(currentBranchProvider, (previous, next) {
      if (previous?.id != next?.id) {
        _load();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Order & Kitchen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  branch?.name ?? 'No branch selected',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: canManage && !_saving
                        ? (value) => setState(() => _enabled = value)
                        : null,
                    secondary: const Icon(Icons.soup_kitchen_outlined),
                    title: const Text('Use Kitchen Display'),
                    subtitle: Text(
                      _enabled
                          ? 'New and added items are sent to KDS. Reducing sent items requires an authorized void with a reason.'
                          : 'No kitchen tickets are created. Held orders can be edited normally until payment.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  pos_ui.OutlinedButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
                if (!canManage) ...[
                  const SizedBox(height: 8),
                  const Text('You can view this setting, but only a manager or administrator can change it.'),
                ],
                const SizedBox(height: 20),
                pos_ui.PrimaryButton(
                  onPressed: canManage && !_saving && branch != null ? _save : null,
                  isLoading: _saving,
                  child: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
