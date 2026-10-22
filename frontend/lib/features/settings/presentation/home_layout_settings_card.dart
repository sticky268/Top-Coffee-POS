import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/home_layout_preference.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;

class HomeLayoutSettingsCard extends ConsumerWidget {
  const HomeLayoutSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(homeLayoutPreferenceProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Home layout', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
              'Choose your home dashboard. Saved on this device for all staff.'),
          const SizedBox(height: 16),
          for (final layout in HomeLayout.values) ...[
            Semantics(
              selected: preference.layout == layout,
              button: true,
              enabled: !preference.saving,
              child: Material(
                color: preference.layout == layout
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: preference.layout == layout
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant),
                ),
                child: pos_ui.ActionSurface(
                  key: ValueKey('home-layout-${layout.name}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: preference.saving
                      ? null
                      : () => ref
                          .read(homeLayoutPreferenceProvider.notifier)
                          .select(layout),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(layout.label,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700))),
                            const SizedBox(width: 12),
                            Icon(preference.layout == layout
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off),
                          ]),
                          const SizedBox(height: 6),
                          Text(layout.description),
                          const SizedBox(height: 12),
                          ExcludeSemantics(
                              child: HomeLayoutMiniature(layout: layout)),
                        ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
              'Layouts adapt to phones, tablets, and light or dark mode. Your role still controls which tools appear.',
              style: theme.textTheme.bodySmall),
          if (preference.saving || preference.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                  liveRegion: true,
                  child: Text(preference.error ?? 'Saving home layout…',
                      style: TextStyle(
                          color: preference.error == null
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error))),
            ),
        ]),
      ),
    );
  }
}

/// Code-drawn layout thumbnails, independent of screen size and sample data.
class HomeLayoutMiniature extends StatelessWidget {
  const HomeLayoutMiniature({super.key, required this.layout});
  final HomeLayout layout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget block(Color color, {int flex = 1}) => Expanded(
          flex: flex,
          child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(5))),
        );
    final neutral = scheme.surfaceContainerHighest;
    final colors = layout == HomeLayout.coffeeCounter
        ? [AppColors.ready, AppColors.caramel, AppColors.info, AppColors.plum]
        : [scheme.primary, neutral, neutral, neutral];
    return Container(
      height: 84,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        if (layout == HomeLayout.classic) block(scheme.primary, flex: 1),
        Expanded(
            flex: 7,
            child: Column(children: [
              Expanded(
                  child: Row(children: [
                for (var index = 0; index < 4; index++)
                  block(colors[index],
                      flex: layout == HomeLayout.modern && index == 0 ? 3 : 1),
              ])),
              Expanded(
                  flex: 2,
                  child: Row(children: [
                    if (layout == HomeLayout.coffeeCounter)
                      block(AppColors.ready, flex: 2),
                    block(neutral, flex: 2),
                    block(layout == HomeLayout.coffeeCounter
                        ? AppColors.caramel
                        : neutral),
                  ])),
            ])),
      ]),
    );
  }
}
