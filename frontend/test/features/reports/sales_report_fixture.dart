import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';

SalesReport salesReportFixture(
        {String period = 'today', String total = '1234567.89'}) =>
    SalesReport({
      'meta': {
        'period': period,
        'date_from': '2026-10-19',
        'date_to': '2026-10-19',
        'previous_from': '2026-10-18',
        'previous_to': '2026-10-18',
        'today': '2026-10-19',
        'generated_at': '2026-10-19T01:00:00Z',
        'branches': [
          {
            'id': 21,
            'name': 'Riverside Coffee and Bakery',
            'timezone': 'Asia/Phnom_Penh'
          }
        ],
        'cashiers': [
          {'id': 16, 'name': 'Manager'}
        ],
        'categories': [
          {'id': 1, 'name': 'Coffee'}
        ],
        'sales_basis': 'Fully paid orders by completion date.',
        'category_basis': 'Whole orders containing selected products.',
        'cash_basis': 'Transaction date; full shifts reconcile separately.',
      },
      'summary': {
        for (final key in SalesReport.moneyKeys) key: total,
        'total_orders': 246,
        'excluded_orders': 0,
        'payment_difference': '0.00'
      },
      'comparisons': {
        for (final key in [...SalesReport.moneyKeys, 'total_orders'])
          key: {
            'previous': '0.00',
            'delta': '1234567.89',
            'percent': null,
            'status': 'new'
          }
      },
      'timeline': [
        for (var month = 1; month <= (period == 'year' ? 12 : 1); month++)
          {
            'date_from': '2026-${month.toString().padLeft(2, '0')}-01',
            'date_to': '2026-${month.toString().padLeft(2, '0')}-28',
            'total': month == 1 ? total : '0.00'
          }
      ],
      'payment_methods': [
        {
          'method': 'cash',
          'count': 246,
          'collected': total,
          'refunds': '0.00',
          'net': total
        }
      ],
      'cash_flow': {
        'collected': total,
        'refunds': '0.00',
        'net': total,
        'unassigned_cash_payments': 0,
        'unassigned_cash_refunds': 0
      },
      'shifts': {'total': 0, 'rows': []},
    });
