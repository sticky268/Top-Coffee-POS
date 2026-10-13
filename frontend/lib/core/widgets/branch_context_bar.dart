import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../branch/current_branch_provider.dart';
import '../offline/order_sync.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/domain/auth_models.dart';

class BranchContextBar extends ConsumerWidget {
  const BranchContextBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthAuthenticated) return const SizedBox.shrink();
    final selected = ref.watch(currentBranchProvider);
    final pending = ref.watch(pendingOrdersProvider);
    final count = pending.asData?.value
        .where((o) => o.status != 'synced')
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (auth.user.branches.length > 1 ||
              auth.user.hasPermission('branches.view-all'))
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: DropdownButton<BranchSummary?>(
                value: selected,
                isExpanded: true,
                hint: const Text('Select branch'),
                items: [
                  if (auth.user.hasPermission('branches.view-all'))
                    const DropdownMenuItem<BranchSummary?>(
                      value: null,
                      child: Text('All branches'),
                    ),
                  ...auth.user.branches.map(
                    (b) => DropdownMenuItem<BranchSummary?>(
                      value: b,
                      child: Text(
                        '${b.name} · ${b.code}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (branch) => ref
                    .read(currentBranchProvider.notifier)
                    .selectBranch(branch),
              ),
            )
          else
            Text(
              selected == null
                  ? 'Select branch'
                  : '${selected.name} · ${selected.code}',
            ),
          if (count != null && count > 0)
            TextButton.icon(
              onPressed: () => context.go('/pending-orders'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text('$count order(s) awaiting confirmation or review'),
            ),
        ],
      ),
    );
  }
}
