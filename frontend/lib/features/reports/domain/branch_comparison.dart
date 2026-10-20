import 'profit_report.dart';
import 'sales_report.dart';

class BranchComparison {
  BranchComparison(this.data) {
    for (final row in [summary, ...branches]) {
      ReportAmount.parse(row['revenue']);
      for (final key in ['cogs', 'gross_profit']) {
        if (row[key] != null) ReportCost.parse(row[key]);
      }
    }
  }
  final Map<String, dynamic> data;
  Map<String, dynamic> get meta => Map<String, dynamic>.from(data['meta']);
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(data['summary']);
  List<Map<String, dynamic>> get branches => SalesReport.maps(data['branches']);
  String get basis =>
      '${meta['basis']} ${meta['cost_basis']} ${meta['comparison_basis']}';
}

String branchChange(Map<String, dynamic> row, String key) {
  final value = row['comparisons'][key] as Map?;
  if (value == null) {
    return 'Comparison unavailable: historical costs incomplete';
  }
  final percent = value['percent'];
  return '${percent == null ? (value['status'] == 'new' ? 'New activity' : 'No change') : '$percent% change'}; previous ${value['previous']}';
}

List<List<Object>> branchComparisonRows(BranchComparison report,
        {bool pdf = false}) =>
    [
      ['Top Coffee POS branch comparison'],
      ['Period', '${report.meta['date_from']} - ${report.meta['date_to']}'],
      [
        'Previous period',
        '${report.meta['previous_from']} - ${report.meta['previous_to']}'
      ],
      [
        'Cashier',
        report.meta['cashier_name']?.toString() ?? 'All sale cashiers'
      ],
      [
        'Category',
        report.meta['category_name']?.toString() ?? 'All historical categories'
      ],
      ['Generated at (UTC)', report.meta['generated_at'] as String],
      if (!pdf) ['Accounting basis', report.basis],
      for (final row in [report.summary, ...report.branches]) ...[
        [],
        [
          row['name'] as String,
          row['timezone']?.toString() ?? 'Branch-local dates'
        ],
        [
          'Revenue rank / share %',
          row['revenue_rank']?.toString() ?? 'Not ranked',
          row['revenue_share_percent']?.toString() ?? 'Unavailable'
        ],
        ['Metric', 'Current', 'Previous', 'Change % / status'],
        for (final key in profitLabels.keys)
          [
            profitLabels[key]!,
            _value(row[key], key),
            _value(row['comparisons'][key]?['previous'], key),
            row['comparisons'][key]?['percent']?.toString() ??
                (row['comparisons'][key]?['status']?.toString() ??
                    'Unavailable'),
          ],
        ['Gross margin %', row['margin_percent']?.toString() ?? 'Unavailable'],
        [
          'Margin change (percentage points)',
          row['margin_change_points']?.toString() ?? 'Unavailable'
        ],
        ['Unknown historical cost lines', row['unknown_cost_lines'] as int],
        [
          'Historical category unknown lines',
          row['legacy_category_lines'] as int
        ],
        ['Known COGS only (not total)', ReportCost.parse(row['known_cogs'])],
        ['Restocked COGS reversed', ReportCost.parse(row['reversed_cogs'])],
      ],
    ];

Object _value(Object? value, String key) {
  if (value == null) return 'Unavailable';
  if (key == 'quantity') return value;
  return key == 'cogs' || key == 'gross_profit'
      ? ReportCost.parse(value)
      : ReportAmount.parse(value);
}
