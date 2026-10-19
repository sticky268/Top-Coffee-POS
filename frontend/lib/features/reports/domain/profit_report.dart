import 'sales_report.dart';

/// Six-decimal historical costs; rounded only for the money label.
class ReportCost extends ReportAmount {
  ReportCost._(this.micros)
      : super((micros.abs() ~/ 10000 + (micros.abs() % 10000 >= 5000 ? 1 : 0)) *
            (micros < 0 ? -1 : 1));
  final int micros;
  factory ReportCost.parse(Object? value) {
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,6}))?$')
        .firstMatch(value?.toString() ?? '');
    if (match == null) {
      throw const FormatException('Invalid historical cost');
    }
    final amount = int.parse(match[2]!) * 1000000 +
        int.parse((match[3] ?? '').padRight(6, '0'));
    return ReportCost._(match[1] == '-' ? -amount : amount);
  }
  @override
  String toString() =>
      '${micros < 0 ? '-' : ''}${micros.abs() ~/ 1000000}.${(micros.abs() % 1000000).toString().padLeft(6, '0')}';
}

class ProfitReport {
  ProfitReport(this.data) {
    ReportAmount.parse(summary['revenue']);
    for (final row in [summary, ...products, ...categories, ...branches]) {
      if (row['cogs'] != null) {
        ReportCost.parse(row['cogs']);
      }
      if (row['gross_profit'] != null) {
        ReportCost.parse(row['gross_profit']);
      }
    }
  }
  final Map<String, dynamic> data;
  Map<String, dynamic> get meta => Map<String, dynamic>.from(data['meta']);
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(data['summary']);
  List<Map<String, dynamic>> get products => SalesReport.maps(data['products']);
  List<Map<String, dynamic>> get categories =>
      SalesReport.maps(data['categories']);
  List<Map<String, dynamic>> get branches => SalesReport.maps(data['branches']);
  List<Map<String, dynamic>> get best => SalesReport.maps(data['best_sellers']);
  List<Map<String, dynamic>> get slow => SalesReport.maps(data['slow_sellers']);
  List<Map<String, dynamic>> get unsold =>
      SalesReport.maps(data['unsold_products']);
}

const profitLabels = {
  'gross': 'Gross item sales',
  'discounts': 'Allocated discounts',
  'tax': 'Original tax',
  'additional': 'Allocated additional charges',
  'refunds': 'Refunds excluding tax',
  'refund_tax': 'Refunded tax (allocated)',
  'non_sales_refunds': 'Refunds above sale value',
  'revenue': 'Revenue excluding tax',
  'cogs': 'Recipe COGS',
  'gross_profit': 'Gross profit',
  'quantity': 'Units sold',
};

String profitValue(Map<String, dynamic> row, String key) {
  if (row[key] == null) {
    return 'Incomplete';
  }
  if (key == 'quantity') {
    return '${row[key]}';
  }
  return key == 'cogs' || key == 'gross_profit'
      ? ReportCost.parse(row[key]).money
      : ReportAmount.parse(row[key]).money;
}

List<List<Object>> profitReportRows(ProfitReport report) => [
      ['Top Coffee POS profitability report'],
      [
        'Branches',
        SalesReport.maps(report.meta['branches'])
            .map((b) => '${b['name']} (${b['timezone']})')
            .join(', ')
      ],
      ['From', report.meta['date_from'] as String],
      ['To', report.meta['date_to'] as String],
      [
        'Previous period',
        '${report.meta['previous_from']} – ${report.meta['previous_to']}'
      ],
      ['Accounting basis', report.meta['basis'] as String],
      ['Cost basis', report.meta['cost_basis'] as String],
      ['Generated at (UTC)', report.meta['generated_at'] as String],
      [],
      ['Metric', 'Current', 'Previous', 'Change %'],
      for (final entry in profitLabels.entries)
        [
          entry.value,
          _exportValue(report.summary, entry.key),
          report.summary['comparisons'][entry.key]?['previous']?.toString() ??
              'Incomplete',
          report.summary['comparisons'][entry.key]?['percent']?.toString() ??
              'No comparable baseline'
        ],
      [
        'Margin %',
        report.summary['margin_percent']?.toString() ??
            'Incomplete / no net revenue'
      ],
      [
        'Margin change (percentage points)',
        report.summary['margin_change_points']?.toString() ??
            'No comparable baseline'
      ],
      ['Unknown cost lines', report.summary['unknown_cost_lines'] as int],
      [
        'Historical category unknown lines',
        report.summary['legacy_category_lines'] as int
      ],
      [
        'Known COGS only (not total)',
        ReportCost.parse(report.summary['known_cogs'])
      ],
      ['Reversed COGS', ReportCost.parse(report.summary['reversed_cogs'])],
      for (final group in {
        'Products': report.products,
        'Categories': report.categories,
        'Branches': report.branches
      }.entries) ...[
        [],
        [
          group.key,
          'Units',
          'Revenue',
          'COGS',
          'Gross profit',
          'Margin %',
          'Unknown cost lines',
          'Revenue change %',
          'Performance'
        ],
        for (final row in group.value)
          [
            row['name'] as String,
            row['quantity'] as int,
            ReportAmount.parse(row['revenue']),
            _exportValue(row, 'cogs'),
            _exportValue(row, 'gross_profit'),
            row['margin_percent']?.toString() ?? 'Unavailable',
            row['unknown_cost_lines'] as int,
            row['comparisons']['revenue']?['percent']?.toString() ??
                'No comparable baseline',
            row['performance']?.toString() ?? ''
          ],
      ],
      [],
      ['Currently available products with no sales'],
      ['Basis', report.meta['unsold_basis'] as String],
      for (final row in report.unsold) [row['name'] as String],
    ];

Object _exportValue(Map<String, dynamic> row, String key) {
  if (row[key] == null) {
    return 'Incomplete';
  }
  if (key == 'quantity') {
    return row[key] as int;
  }
  return key == 'cogs' || key == 'gross_profit'
      ? ReportCost.parse(row[key])
      : ReportAmount.parse(row[key]);
}

/// Narrow PDF tables retain every field without nine cramped columns.
List<List<Object>> profitReportPdfRows(ProfitReport report) => [
      for (final row in profitReportRows(report))
        if (row.length <= 4)
          row
        else ...[
          [row[0], row[2], row[3], row[4]],
          ['Units / margin %', row[1], row[5]],
          ['Unknown cost lines / revenue change %', row[6], row[7]],
          ['Performance', row[8]],
        ],
    ];
