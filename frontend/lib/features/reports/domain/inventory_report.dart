import 'sales_report.dart';

const inventorySummaryLabels = {
  'value': 'Closing stock valuation',
  'known_value': 'Known valuation subtotal',
  'waste_cost': 'Recorded waste cost',
  'known_waste_cost': 'Known waste cost subtotal',
  'low_stock_items': 'Low-stock ingredients',
  'unknown_value_items': 'Ingredients with unknown valuation',
  'variance_items': 'Ingredients with sale-usage variance',
  'missing_recipe_lines': 'Sales lines without recipe history',
  'ledger_review_items': 'Ingredients requiring ledger review',
  'sales': 'Paid orders in usage cohort',
};
const inventoryLabels = {
  'opening': 'Opening ledger quantity',
  'closing': 'Closing ledger quantity',
  'value': 'Closing valuation',
  'waste': 'Recorded waste quantity',
  'waste_cost': 'Recorded waste cost',
  'adjustments': 'Net adjustments / transfers',
  'deducted': 'Actual gross sale deductions',
  'expected': 'Theoretical recipe usage',
  'variance': 'Actual minus theoretical usage',
  'returned': 'Sale returns through end date',
};
const inventoryCostKeys = [
  'value',
  'known_value',
  'waste_cost',
  'known_waste_cost',
];

/// Numeric spreadsheet quantity, retaining three decimals without doubles.
class ReportQuantity extends ReportAmount {
  ReportQuantity(this.value) : super(0) {
    if (!RegExp(r'^-?\d+\.\d{3}$').hasMatch(value)) {
      throw const FormatException('Invalid inventory quantity');
    }
  }
  final String value;
  @override
  String toString() => value;
}

/// Decimal cost text stays exact even beyond native integer bounds.
class ReportInventoryCost extends ReportAmount {
  ReportInventoryCost.parse(Object value)
      : value = value.toString(),
        super(0) {
    if (!RegExp(r'^-?\d+\.\d{6}$').hasMatch(this.value)) {
      throw const FormatException('Invalid inventory cost');
    }
  }
  final String value;
  @override
  String toString() => value;
}

String inventoryValue(Map<String, dynamic> row, String key, {String? unit}) {
  final value = row[key];
  if (value == null) return 'Unavailable';
  if (inventoryCostKeys.contains(key)) return '\$$value';
  return '$value${unit == null ? '' : ' $unit'}';
}

String inventoryChange(Map<String, dynamic> row, String key) {
  final c = row['comparisons'][key];
  if (c == null) return 'Incomplete comparison';
  if (c['percent'] != null) return '${c['percent']}% vs previous';
  return c['status'] == 'new' ? 'New activity' : 'No comparable baseline';
}

List<List<Object>> inventoryReportRows(Map<String, dynamic> data,
    {bool includeBasis = true}) {
  final meta = data['meta'];
  Object value(Object? v, String key, {bool quantity = false}) => v == null
      ? 'Unavailable'
      : inventoryCostKeys.contains(key)
          ? ReportInventoryCost.parse(v)
          : quantity
              ? ReportQuantity(v.toString())
              : int.tryParse(v.toString()) ?? v;
  List<List<Object>> metrics(
    Map<String, dynamic> row,
    Map<String, String> labels, {
    bool quantity = false,
  }) =>
      [
        ['Metric', 'Current', 'Previous', 'Change %'],
        for (final entry in labels.entries)
          [
            entry.value,
            value(row[entry.key], entry.key, quantity: quantity),
            value(
              row['comparisons'][entry.key]?['previous'],
              entry.key,
              quantity: quantity,
            ),
            row['comparisons'][entry.key]?['percent']?.toString() ??
                'Unavailable baseline',
          ],
      ];
  return [
    ['Top Coffee POS inventory report'],
    [
      'Branches',
      SalesReport.maps(
        meta['branches'],
      ).map((b) => '${b['name']} / ${b['timezone']}').join('; '),
    ],
    ['From', meta['date_from']],
    ['To', meta['date_to']],
    ['Previous period', '${meta['previous_from']} - ${meta['previous_to']}'],
    ['Sales usage cashier', meta['cashier_name'] ?? 'All'],
    ['Sales usage category (whole orders)', meta['category_name'] ?? 'All'],
    ['Stock / waste scope', 'All cashiers and categories in selected branches'],
    if (includeBasis) ['Accounting basis', meta['basis']],
    ['Generated UTC', meta['generated_at']],
    [],
    ['Branch-wide stock / waste and selected sale-usage coverage'],
    ...metrics(
      Map<String, dynamic>.from(data['summary']),
      inventorySummaryLabels,
    ),
    for (final row in SalesReport.maps(data['ingredients'])) ...[
      [],
      ['Ingredient', row['name']],
      ['Branch / unit', '${row['branch_name']} / ${row['unit']}'],
      ['Current catalogue threshold', ReportQuantity(row['threshold'])],
      [
        'Status',
        '${row['active'] ? 'Active' : 'Archived / inactive'}${row['low_stock'] ? ' / low stock' : ''}${row['ledger_review'] ? ' / ledger review' : ''}',
      ],
      ...metrics(row, inventoryLabels, quantity: true),
      ['Known recipe usage subtotal', ReportQuantity(row['known_expected'])],
      [
        'Known waste cost subtotal',
        ReportInventoryCost.parse(row['known_waste_cost'])
      ],
    ],
  ];
}
