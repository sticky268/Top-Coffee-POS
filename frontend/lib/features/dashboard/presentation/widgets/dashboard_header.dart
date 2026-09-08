import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../../core/branch/current_branch_provider.dart';

class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({
    super.key,
    required this.user,
    required this.onLogout,
  });

  final AuthenticatedUser user;
  final VoidCallback onLogout;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE, MMMM d').format(DateTime.now());
    final roleLabel = user.roles.isNotEmpty ? user.roles.first : null;
    final currentBranch = ref.watch(currentBranchProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.local_cafe_rounded,
          color: theme.colorScheme.primary,
          size: 32,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Coffee POS',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$_greeting, ${user.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (roleLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        roleLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (user.branches.length > 1) ...[
                const SizedBox(height: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<BranchSummary>(
                    value: currentBranch,
                    isDense: true,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    hint: const Text('Select branch'),
                    items: user.branches.map((branch) {
                      return DropdownMenuItem<BranchSummary>(
                        value: branch,
                        child: Text(
                          '${branch.name} (${branch.code})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (branch) {
                      if (branch != null) {
                        ref
                            .read(currentBranchProvider.notifier)
                            .selectBranch(branch);
                      }
                    },
                  ),
                ),
              ] else if (currentBranch != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${currentBranch.name} (${currentBranch.code})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notifications',
          onPressed: null,
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Log out',
          onPressed: onLogout,
        ),
      ],
    );
  }
}