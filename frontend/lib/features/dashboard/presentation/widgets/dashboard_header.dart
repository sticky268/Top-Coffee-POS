import 'package:flutter/material.dart';
import '../../../../core/theme/coffee_studio_theme.dart';
import 'studio_dashboard_cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/branch/current_branch_provider.dart';
import '../../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../auth/domain/auth_models.dart';

class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({
    super.key,
    required this.user,
    required this.onLogout,
    this.showBrand = true,
  });

  final AuthenticatedUser user;
  final VoidCallback onLogout;
  final bool showBrand;

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
    final canViewAllBranches = user.hasPermission('branches.view-all');

    if (CoffeeStudioTheme.active(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          final controlWidth = box.maxWidth.clamp(0.0, 260.0);
          final names =
              user.name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
          final initials =
              names.take(2).map((s) => s.characters.first).join().toUpperCase();
          final role = roleLabel == null || roleLabel.isEmpty
              ? null
              : '${roleLabel[0].toUpperCase()}${roleLabel.substring(1).replaceAll('_', ' ')}';
          return Wrap(
              alignment: WrapAlignment.end,
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                    key: const ValueKey('studio-branch-control'),
                    width: controlWidth,
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.storefront_outlined,
                          size: 22, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 10),
                      Expanded(
                          child: user.branches.length > 1 || canViewAllBranches
                              ? DropdownButtonHideUnderline(
                                  child: DropdownButton<BranchSummary?>(
                                  value: currentBranch,
                                  isExpanded: true,
                                  icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded),
                                  hint: const Text('Select branch'),
                                  style: theme.textTheme.titleSmall,
                                  items: [
                                    if (canViewAllBranches)
                                      const DropdownMenuItem<BranchSummary?>(
                                          value: null,
                                          child: Text('All Branches')),
                                    for (final branch in user.branches)
                                      DropdownMenuItem<BranchSummary?>(
                                          value: branch,
                                          child: Text(branch.name,
                                              overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (branch) => ref
                                      .read(currentBranchProvider.notifier)
                                      .selectBranch(branch),
                                ))
                              : Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                      currentBranch?.name ?? 'Select branch',
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis))),
                    ])),
                ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: box.maxWidth.clamp(0.0, 300.0)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ExcludeSemantics(
                          child: CircleAvatar(
                              radius: 22,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: initials.isEmpty
                                  ? const Icon(Icons.person_outline)
                                  : Text(initials))),
                      const SizedBox(width: 12),
                      Flexible(
                          child: Column(
                              key: const ValueKey('studio-user-identity'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(user.name,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            if (role != null) ...[
                              const SizedBox(height: 3),
                              Text(role,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant))
                            ],
                          ])),
                      const SizedBox(width: 18),
                      Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration: BoxDecoration(
                              border: Border(
                                  left: BorderSide(
                                      color:
                                          theme.colorScheme.outlineVariant))),
                          child: pos_ui.IconButton(
                              icon: const Icon(Icons.logout, size: 24),
                              tooltip: 'Log out',
                              onPressed: onLogout)),
                    ])),
              ]);
        }),
        const SizedBox(height: 12),
        StudioWelcomeBanner(greeting: '$_greeting, ${user.name}!'),
      ]);
    }

    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBrand) ...[
          Text('Top Coffee POS', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
        ],
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$_greeting, ${user.name}',
              style: (CoffeeStudioTheme.active(context)
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight:
                    CoffeeStudioTheme.active(context) ? FontWeight.w700 : null,
                color: CoffeeStudioTheme.active(context)
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
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
        if (user.branches.length > 1 || canViewAllBranches) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<BranchSummary?>(
                    value: currentBranch,
                    isDense: false,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    hint: const Text('Select branch'),
                    items: [
                      if (canViewAllBranches)
                        const DropdownMenuItem<BranchSummary?>(
                          value: null,
                          child: Text('All Branches'),
                        ),
                      ...user.branches.map((branch) {
                        return DropdownMenuItem<BranchSummary?>(
                          value: branch,
                          child: Text(
                            '${branch.name} (${branch.code})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (branch) {
                      ref
                          .read(currentBranchProvider.notifier)
                          .selectBranch(branch);
                    },
                  ),
                ),
              ),
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
    );
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
      pos_ui.IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Log out',
        onPressed: onLogout,
      ),
    ]);
    final brandIcon = Icon(Icons.local_cafe_rounded,
        color: theme.colorScheme.primary, size: 32);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                if (showBrand) brandIcon,
                const Spacer(),
                controls
              ]),
              const SizedBox(height: 8),
              information,
            ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showBrand) ...[brandIcon, const SizedBox(width: 16)],
        Expanded(child: information),
        controls,
      ]);
    });
  }
}
