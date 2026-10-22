import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

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
      this.notes = const [],
      this.onPeriodChanged,
      this.selectedPeriod});
  final Map<String, dynamic> meta;
  final String scope, filterLabel;
  final VoidCallback onChangeFilters;
  final List<Widget> notes;
  final ValueChanged<String>? onPeriodChanged;
  final String? selectedPeriod;

  String date(Object? value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null ? '$value' : DateFormat('dd MMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onPeriodChanged != null)
            ReportPeriodChips(
                selected: selectedPeriod, onSelected: onPeriodChanged!),
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

  IconData get icon => switch (label.toLowerCase()) {
        final text when text.contains('profit') => Icons.trending_up_rounded,
        final text when text.contains('cost') || text.contains('waste') =>
          Icons.receipt_long_outlined,
        final text when text.contains('order') => Icons.shopping_bag_outlined,
        final text
            when text.contains('stock') ||
                text.contains('ingredient') ||
                text.contains('units') =>
          Icons.inventory_2_outlined,
        final text when text.contains('refund') => Icons.undo_rounded,
        _ => Icons.payments_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.semantic(context, AppColors.ready);
    final ink =
        prominent ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: prominent
            ? LinearGradient(
                colors: dark
                    ? const [Color(0xFF204B46), Color(0xFF153832)]
                    : const [Color(0xFF24675E), Color(0xFF194B43)])
            : null,
        color: prominent ? null : Theme.of(context).colorScheme.surface,
        border: prominent
            ? null
            : Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .6)),
      ),
      child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: EdgeInsets.all(prominent ? 24 : 18),
            title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                          color: prominent
                              ? Colors.white.withValues(alpha: .12)
                              : accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon,
                          size: 22, color: prominent ? Colors.white : accent)),
                  Text(label,
                      style: TextStyle(color: ink.withValues(alpha: .85))),
                ]),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reportDisplayValue(value),
                        style: (prominent
                                ? Theme.of(context).textTheme.headlineLarge
                                : Theme.of(context).textTheme.headlineSmall)
                            ?.copyWith(
                                color: ink, fontWeight: FontWeight.w800)),
                    if (caption != null) ...[
                      const SizedBox(height: 8),
                      Text(caption!,
                          style: TextStyle(color: ink.withValues(alpha: .8)))
                    ],
                  ],
                )),
            trailing: onTap == null
                ? null
                : Icon(Icons.arrow_outward_rounded,
                    size: 20, color: ink.withValues(alpha: .7)),
            onTap: onTap,
          )),
    );
  }
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

class ReportPeriodChips extends StatelessWidget {
  const ReportPeriodChips({super.key, required this.onSelected, this.selected});
  final String? selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final period in const {
            'today': 'Today',
            'last7': '7 days',
            'last30': '30 days',
            'this_month': 'This month'
          }.entries)
            ChoiceChip(
                label: Text(period.value),
                selected: selected == period.key,
                onSelected: (_) => onSelected(period.key)),
        ]),
      );
}

class ReportIntro extends StatelessWidget {
  const ReportIntro(
      {super.key,
      required this.title,
      required this.subtitle,
      this.icon = Icons.insights_rounded});
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: AppColors.tint(context, AppColors.ready),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppColors.semantic(context, AppColors.ready)
                    .withValues(alpha: .18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 32, color: AppColors.semantic(context, AppColors.ready)),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

class ReportRankingPreview extends StatelessWidget {
  const ReportRankingPreview(
      {super.key,
      required this.title,
      required this.rows,
      required this.value,
      required this.onSelect,
      this.noun = 'products'});
  final String title;
  final String noun;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) value;
  final ValueChanged<Map<String, dynamic>> onSelect;
  Widget row(BuildContext context, Map<String, dynamic> item, int index,
          {VoidCallback? tap}) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.tint(context, AppColors.ready),
            child: Text('${index + 1}',
                style: TextStyle(
                    color: AppColors.semantic(context, AppColors.ready)))),
        title: Text(item['name'] as String),
        subtitle: Text(value(item)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: tap ?? () => onSelect(item),
      );
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.all(18),
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          const Divider(height: 1),
          if (rows.isEmpty)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No paid $noun sales in this period.')),
          for (var i = 0; i < rows.length && i < 3; i++)
            row(context, rows[i], i),
          if (rows.length > 3)
            Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (sheetContext) => SafeArea(
                            child: FractionallySizedBox(
                                heightFactor: .8,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Text(title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge)),
                                      Expanded(
                                          child: ListView(children: [
                                        for (var i = 0; i < rows.length; i++)
                                          row(sheetContext, rows[i], i,
                                              tap: () {
                                            Navigator.of(sheetContext).pop();
                                            onSelect(rows[i]);
                                          })
                                      ])),
                                    ])))),
                    child: Text('View all ${rows.length} $noun'))),
        ]),
      );
}
