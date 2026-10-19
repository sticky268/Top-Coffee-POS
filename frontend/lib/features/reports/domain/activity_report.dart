import 'sales_report.dart';

const activityLabels = {
  'sales': 'Paid sales including tax',
  'discounts': 'Discounts',
  'refunds': 'Sale-linked refunds',
  'net_sales': 'Net sales including tax',
  'orders': 'Paid orders',
  'discounted_orders': 'Discounted orders',
  'refunded_orders': 'Refunded orders',
  'voids': 'Audited voids',
};
const activityMoney = ['sales', 'discounts', 'refunds', 'net_sales'];
const activityDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const activityRates = {
  'discounted_orders': 'Discount rate',
  'refunded_orders': 'Refund rate',
  'voids': 'Void rate'
};

String activityValue(Map<String, dynamic> row, String key) =>
    activityMoney.contains(key)
        ? ReportAmount.parse(row[key]).money
        : '${row[key]}';
String activityChange(Map<String, dynamic> row, String key) {
  final c = row['comparisons'][key];
  return c['percent'] == null
      ? (c['status'] == 'new' ? 'New activity' : 'No comparable baseline')
      : '${c['percent']}% vs previous';
}

String activityPoint(Map<String, dynamic> row) =>
    '${activityDays[(row['weekday'] as int) - 1]} ${row['hour'].toString().padLeft(2, '0')}:00';
Object _value(Map<String, dynamic> row, String key, {bool previous = false}) {
  final value = previous ? row['comparisons'][key]['previous'] : row[key];
  return activityMoney.contains(key) ? ReportAmount.parse(value) : value as int;
}

List<List<Object>> activityReportRows(Map<String, dynamic> report,
    {bool compact = false}) {
  final meta = Map<String, dynamic>.from(report['meta']);
  List<List<Object>> metrics(Map<String, dynamic> row) => [
        ['Metric', 'Current', 'Previous', 'Change %'],
        for (final key in activityLabels.keys)
          [
            activityLabels[key]!,
            _value(row, key),
            _value(row, key, previous: true),
            row['comparisons'][key]['percent']?.toString() ??
                'No comparable baseline'
          ],
        ['Rate %', 'Current', 'Previous', 'Change (points)'],
        for (final key in activityRates.keys)
          [
            activityRates[key]!,
            row['${key}_rate']?.toString() ?? 'Unavailable',
            row['${key}_previous_rate']?.toString() ?? 'Unavailable',
            row['${key}_change_points']?.toString() ?? 'Unavailable'
          ],
      ];
  return [
    ['Top Coffee POS time and cashier report'],
    [
      'Branches',
      SalesReport.maps(meta['branches'])
          .map((b) => '${b['name']} (${b['timezone']})')
          .join(', ')
    ],
    ['From', meta['date_from'] as String],
    ['To', meta['date_to'] as String],
    ['Previous period', '${meta['previous_from']} - ${meta['previous_to']}'],
    [
      'Cashier',
      meta['cashier_name']?.toString() ?? 'All original sale cashiers'
    ],
    ['Category', meta['category_name']?.toString() ?? 'All current categories'],
    ['Accounting basis', meta['basis'] as String],
    ['Flag policy', meta['flag_basis'] as String],
    ['Generated (UTC)', meta['generated_at'] as String],
    [
      'Heatmap export',
      compact
          ? 'Cells with no paid orders in either period are omitted; CSV and Excel include all 168 cells.'
          : 'All 168 local weekday/hour cells.'
    ],
    [],
    ...metrics(Map<String, dynamic>.from(report['summary'])),
    [],
    ['Weekday / hour heatmap'],
    ['Local weekday / hour / metric', 'Current', 'Previous', 'Change %'],
    for (final cell in SalesReport.maps(report['cells']).where((c) =>
        !compact ||
        c['orders'] != 0 ||
        c['comparisons']['orders']['previous'] != 0))
      for (final key in ['orders', 'net_sales'])
        [
          '${activityPoint(cell)} / ${activityLabels[key]}',
          _value(cell, key),
          _value(cell, key, previous: true),
          cell['comparisons'][key]['percent']?.toString() ??
              'No comparable baseline'
        ],
    for (final row in SalesReport.maps(report['cashiers'])) ...[
      [],
      ['Cashier', row['name'] as String],
      [
        'Review flags',
        (row['flags'] as List).map((key) => activityRates[key]).join(', ')
      ],
      ...metrics(row),
    ]
  ];
}
