import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Groups detail without competing with the report's main figures.
class ReportSection extends StatelessWidget {
  const ReportSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          key: PageStorageKey(title),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class ReportHeader extends StatelessWidget {
  const ReportHeader(
      {super.key,
      required this.meta,
      required this.scope,
      required this.filterLabel,
      required this.onChangeFilters,
      this.notes = const []});
  final Map<String, dynamic> meta;
  final String scope, filterLabel;
  final VoidCallback onChangeFilters;
  final List<Widget> notes;

  String date(Object? value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null ? '$value' : DateFormat('dd MMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(scope, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
              meta['date_from'] == meta['date_to']
                  ? date(meta['date_from'])
                  : '${date(meta['date_from'])} – ${date(meta['date_to'])}',
              style: Theme.of(context).textTheme.titleMedium),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: onChangeFilters,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(filterLabel))),
          if (meta['cashier_name'] != null || meta['category_name'] != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'Cashier: ${meta['cashier_name'] ?? 'All'} · Category: ${meta['category_name'] ?? 'All'}')),
          ReportSection(title: 'Report scope & comparison', children: [
            Text(
                'Previous period: ${date(meta['previous_from'])} – ${date(meta['previous_to'])}'),
            Text(
                'Cashier: ${meta['cashier_name'] ?? 'All'} · Category: ${meta['category_name'] ?? 'All'}'),
            for (final branch in (meta['branches'] as List? ?? const []))
              Text('${branch['name']} · ${branch['timezone']}'),
            ...notes,
          ]),
        ],
      );
}

/// Groups digits without converting precise monetary text to floating point.
String reportDisplayValue(String value) => value.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+\.)'), (match) => '${match[1]},');

class ReportMetricTile extends StatelessWidget {
  const ReportMetricTile(
      {super.key,
      required this.label,
      required this.value,
      this.onTap,
      this.prominent = false,
      this.caption});
  final String label, value;
  final String? caption;
  final bool prominent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color:
            prominent ? Theme.of(context).colorScheme.primaryContainer : null,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(label),
          subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reportDisplayValue(value),
                      style: (prominent
                              ? Theme.of(context).textTheme.headlineMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  if (caption != null) ...[
                    const SizedBox(height: 6),
                    Text(caption!),
                  ],
                ],
              )),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class ReportOverview extends StatelessWidget {
  const ReportOverview(
      {super.key, required this.primary, required this.metrics});
  final Widget primary;
  final List<Widget> metrics;
  @override
  Widget build(BuildContext context) => Column(children: [
        primary,
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 700 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 20
              ? 3
              : 1;
          return Wrap(spacing: 8, children: [
            for (final metric in metrics)
              SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                  child: metric),
          ]);
        }),
        const SizedBox(height: 8),
      ]);
}
