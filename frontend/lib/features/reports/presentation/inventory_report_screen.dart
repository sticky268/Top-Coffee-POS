import 'package:flutter/material.dart';
import 'report_overview_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/page_content.dart';
import '../data/report_exporter.dart';
import '../data/sales_reports_repository.dart';
import '../domain/inventory_report.dart';
import '../domain/profit_report.dart' show ReportCost;
import '../domain/sales_report.dart';

class InventoryReportScreen extends ConsumerStatefulWidget {
  const InventoryReportScreen({
    super.key,
    required this.query,
    required this.branchId,
    this.onChangeFilters,
  });
  final SalesReportQuery query;
  final int? branchId;
  final VoidCallback? onChangeFilters;
  @override
  ConsumerState<InventoryReportScreen> createState() =>
      _InventoryReportScreenState();
}

class _InventoryReportScreenState extends ConsumerState<InventoryReportScreen> {
  late Future<Map<String, dynamic>> request;
  String view = 'All';
  bool exporting = false;
  Future<Map<String, dynamic>> load() => ref
      .read(salesReportsRepositoryProvider)
      .inventory(widget.query, widget.branchId);
  @override
  void initState() {
    super.initState();
    request = load();
  }

  void sources(Map<String, dynamic> ingredient, String kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventorySourcesScreen(
          query: widget.query,
          branchId: widget.branchId,
          ingredientId: ingredient['id'] as int,
          kind: kind,
        ),
      ),
    );
  }

  bool visible(Map<String, dynamic> r) => switch (view) {
        'Low stock' => r['low_stock'] == true,
        'Waste' => r['waste'] != '0.000',
        'Variance' => r['variance'] != null && r['variance'] != '0.000',
        'Incomplete' => r['value'] == null ||
            r['expected'] == null ||
            r['waste_cost'] == null ||
            r['ledger_review'] == true,
        _ => true,
      };
  Future<void> export(
    Map<String, dynamic> data,
    ReportExportFormat format,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final file = await ReportExporter.buildRows(
        inventoryReportRows(data,
            includeBasis: format != ReportExportFormat.pdf),
        'top-coffee-inventory-${data['meta']['date_from']}-${data['meta']['date_to']}',
        format,
        notes: format == ReportExportFormat.pdf
            ? data['meta']['basis'] as String
            : null,
        title: 'Inventory report',
        columnFlex: [5, 3, 3, 3],
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              mimeType: file.mimeType,
              name: file.name,
            ),
          ],
          fileNameOverrides: [file.name],
          subject: 'Top Coffee POS inventory report',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not export. Retry or select one branch for a smaller report.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Inventory report')),
        body: PageContent(
          maxWidth: 1100,
          child: FutureBuilder<Map<String, dynamic>>(
            future: request,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: () => setState(() {
                      request = load();
                    }),
                    child: const Text('Retry inventory report'),
                  ),
                );
              }
              final data = state.requireData;
              final meta = data['meta'];
              final summary = Map<String, dynamic>.from(data['summary']);
              final rows = SalesReport.maps(
                data['ingredients'],
              ).where(visible).toList();
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    request = load();
                  });
                  try {
                    await request;
                  } catch (_) {
                    /* FutureBuilder shows the retry action. */
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ReportHeader(
                      meta: Map<String, dynamic>.from(meta),
                      scope: SalesReport.maps(meta['branches'])
                          .map((b) => '${b['name']}')
                          .join(', '),
                      filterLabel: 'Change date and report filters',
                      onChangeFilters: widget.onChangeFilters ??
                          () => Navigator.pop(context),
                      notes: const [
                        Text(
                            'Stock and waste include all cashiers and categories. Valuation replays the ledger; low stock uses current reorder thresholds.')
                      ],
                    ),
                    if (summary['unknown_value_items'] != 0 ||
                        summary['ledger_review_items'] != 0)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              '${summary['unknown_value_items']} ingredient(s) have unknown valuation · ${summary['ledger_review_items']} need ledger review. Known costs are subtotals.')),
                    ReportOverview(
                      primary: ReportMetricTile(
                          label: inventorySummaryLabels['value']!,
                          value: summary['value'] == null
                              ? 'Unavailable'
                              : ReportCost.parse(summary['value']).money,
                          prominent: true,
                          caption:
                              'At period end · rounded to cents. Exact costs are in the details.',
                          onTap: () => setState(() => view = 'All')),
                      metrics: [
                        for (final key in [
                          'waste_cost',
                          'low_stock_items',
                          'unknown_value_items'
                        ])
                          ReportMetricTile(
                              label: inventorySummaryLabels[key]!,
                              value: inventoryCostKeys.contains(key) &&
                                      summary[key] != null
                                  ? ReportCost.parse(summary[key]).money
                                  : inventoryValue(summary, key),
                              onTap: () =>
                                  setState(() => view = key == 'waste_cost'
                                      ? 'Waste'
                                      : key == 'low_stock_items'
                                          ? 'Low stock'
                                          : 'Incomplete')),
                      ],
                    ),
                    ReportSection(
                        title: 'Stock value & previous-period changes',
                        children: [
                          for (final key in [
                            'value',
                            'waste_cost',
                            'low_stock_items',
                            'unknown_value_items'
                          ])
                            ListTile(
                                title: Text(inventorySummaryLabels[key]!),
                                subtitle: Text(
                                    '${inventoryValue(summary, key)}\n${inventoryChange(summary, key)}')),
                          Text(
                            'Known valuation subtotal: ${inventoryValue(summary, 'known_value')} / known waste subtotal: ${inventoryValue(summary, 'known_waste_cost')}',
                          ),
                        ]),
                    ReportSection(title: 'Selected sales usage', children: [
                      const SizedBox(height: 16),
                      Text(
                        'Cashier: ${meta['cashier_name'] ?? 'All'} / whole-order category: ${meta['category_name'] ?? 'All'}',
                      ),
                      const Text(
                        'Gross sale deductions versus recipe quantities saved at completion. Returns are separate. Variance is a ledger/recipe discrepancy, not a physical stocktake.',
                      ),
                      for (final key in [
                        'sales',
                        'variance_items',
                        'missing_recipe_lines',
                        'ledger_review_items',
                      ])
                        ListTile(
                          title: Text(inventorySummaryLabels[key]!),
                          subtitle: Text(
                            '${inventoryValue(summary, key)}\n${inventoryChange(summary, key)}',
                          ),
                          onTap: () => setState(() {
                            view = key == 'variance_items'
                                ? 'Variance'
                                : key == 'sales'
                                    ? 'All'
                                    : 'Incomplete';
                          }),
                        ),
                    ]),
                    ReportSection(
                      title: 'Accounting and data coverage',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(meta['basis'] as String),
                        ),
                      ],
                    ),
                    const Text('Exports include all ingredients.'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final format in ReportExportFormat.values)
                          OutlinedButton(
                            onPressed:
                                exporting ? null : () => export(data, format),
                            child: Text('Export ${format.name.toUpperCase()}'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ingredient details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                        'Choose a view, then tap an ingredient for stock movements.'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final label in [
                          'All',
                          'Low stock',
                          'Waste',
                          'Variance',
                          'Incomplete',
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: view == label,
                            onSelected: (_) => setState(() => view = label),
                          ),
                      ],
                    ),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No ingredients match this view.'),
                      ),
                    for (final row in rows)
                      ExpansionTile(
                        key: ValueKey('inventory-ingredient-${row['id']}'),
                        title: Text('${row['name']} / ${row['branch_name']}'),
                        subtitle: Text(
                          '${row['closing']} ${row['unit']} / ${inventoryValue(row, 'value')}\n${row['low_stock'] ? 'Low stock' : row['active'] ? 'Active' : 'Archived / inactive'}${row['ledger_review'] ? ' / ledger review' : ''}',
                        ),
                        children: [
                          Text(
                            'Current threshold: ${row['threshold']} ${row['unit']}',
                          ),
                          for (final key in inventoryLabels.keys)
                            ListTile(
                              title: Text(inventoryLabels[key]!),
                              subtitle: Text(
                                '${inventoryValue(row, key, unit: inventoryCostKeys.contains(key) ? null : row['unit'] as String)}\n${inventoryChange(row, key)}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => sources(
                                row,
                                [
                                  'expected',
                                  'variance',
                                  'deducted',
                                  'returned',
                                ].contains(key)
                                    ? 'sales'
                                    : key == 'opening'
                                        ? 'opening'
                                        : ['closing', 'value'].contains(key)
                                            ? 'closing'
                                            : ['waste', 'waste_cost']
                                                    .contains(key)
                                                ? 'waste'
                                                : 'ledger',
                              ),
                            ),
                          Text(
                            'Known recipe subtotal: ${row['known_expected']} ${row['unit']}',
                          ),
                          TextButton(
                            onPressed: () => sources(row, 'ledger'),
                            child: const Text('Period ledger movements'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class InventorySourcesScreen extends ConsumerStatefulWidget {
  const InventorySourcesScreen({
    super.key,
    required this.query,
    required this.branchId,
    required this.ingredientId,
    required this.kind,
  });
  final SalesReportQuery query;
  final int? branchId;
  final int ingredientId;
  final String kind;
  @override
  ConsumerState<InventorySourcesScreen> createState() =>
      _InventorySourcesScreenState();
}

class _InventorySourcesScreenState
    extends ConsumerState<InventorySourcesScreen> {
  late Future<Map<String, dynamic>> request;
  int page = 1;
  Future<Map<String, dynamic>> load() =>
      ref.read(salesReportsRepositoryProvider).inventory(
            widget.query,
            widget.branchId,
            detail: true,
            ingredientId: widget.ingredientId,
            kind: widget.kind,
            page: page,
          );
  @override
  void initState() {
    super.initState();
    request = load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const PageAppBar(title: Text('Inventory source records')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: request,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError) {
              return Center(
                child: FilledButton(
                  onPressed: () => setState(() {
                    request = load();
                  }),
                  child: const Text('Retry inventory sources'),
                ),
              );
            }
            final data = state.requireData;
            final ingredient = data['ingredient'];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${ingredient['name']} / ${ingredient['branch_name']} / ${ingredient['unit']}',
                ),
                Text(
                  '${widget.query.dateFrom} - ${widget.query.dateTo} / ${widget.kind}\nPage ${data['page']} / ${data['total']} source records',
                ),
                Text(
                  widget.kind == 'sales'
                      ? 'Selected paid-sale cohort; historical recipe coverage may be incomplete. Gross deductions and returns through the selected end date are separate.'
                      : 'Branch-wide ledger evidence. Cashier and product category filters do not narrow stock or waste.',
                ),
                if ((data['rows'] as List).isEmpty)
                  const Text('No matching source records.'),
                for (final row in SalesReport.maps(data['rows']))
                  if (widget.kind == 'sales')
                    ListTile(
                      title: Text(
                        'Order ${row['order_number'] ?? row['order_id']}',
                      ),
                      subtitle: Text(
                        'Theoretical: ${row['expected'] ?? 'Unavailable'} / actual: ${row['deducted']} / returns: ${row['returned']} ${ingredient['unit']}\nMissing recipe lines: ${row['missing_recipe_lines']}',
                      ),
                    )
                  else
                    ListTile(
                      title: Text(
                        'Movement ${row['movement_id']} / ${row['type']}',
                      ),
                      subtitle: Text(
                        '${row['quantity']} ${ingredient['unit']} / unit cost: ${row['unit_cost'] ?? 'Unavailable'}\n${row['occurred_at_local']} / ${row['actor']}\n${row['reason'] ?? 'No reason recorded'}\nReference: ${row['reference_type'] ?? '-'} #${row['reference_id'] ?? '-'}',
                      ),
                    ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: page <= 1
                          ? null
                          : () => setState(() {
                                page--;
                                request = load();
                              }),
                      child: const Text('Previous'),
                    ),
                    OutlinedButton(
                      onPressed: page * 50 >= (data['total'] as int)
                          ? null
                          : () => setState(() {
                                page++;
                                request = load();
                              }),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}
