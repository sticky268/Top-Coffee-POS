import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_preference.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;

class AppDesignSettingsCard extends ConsumerWidget {
  const AppDesignSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(appDesignPreferenceProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('App theme', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Choose how the app looks on this device.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (final design in AppDesign.values) ...[
              Builder(builder: (context) {
                final option = (
                  design,
                  design.label,
                  design.description,
                  design == AppDesign.original
                      ? Icons.history
                      : Icons.palette_outlined
                );

                final selected = preference.layout == option.$1;
                return Semantics(
                  selected: selected,
                  button: true,
                  enabled: !preference.saving,
                  child: Material(
                    color: selected ? scheme.primaryContainer : scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: selected
                              ? scheme.primary
                              : scheme.outlineVariant),
                    ),
                    child: pos_ui.ActionSurface(
                      key: ValueKey('app-design-${option.$1.name}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: preference.saving
                          ? null
                          : () => ref
                              .read(appDesignPreferenceProvider.notifier)
                              .select(option.$1),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Icon(option.$4,
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.$2,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurface,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(option.$3,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant)),
                            ],
                          )),
                          const SizedBox(width: 12),
                          Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
            Text('Saved on this device for all staff.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (preference.saving || preference.error != null) ...[
              const SizedBox(height: 10),
              Semantics(
                  liveRegion: true,
                  child: Text(preference.error ?? 'Saving app theme…',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: preference.error == null
                              ? scheme.onSurfaceVariant
                              : scheme.error))),
            ],
          ],
        ),
      ),
    );
  }
}
