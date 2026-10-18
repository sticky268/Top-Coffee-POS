import 'package:flutter/foundation.dart';

/// Exact report money. Only chart geometry may convert cents to a ratio.
@immutable
class ReportAmount {
  const ReportAmount(this.cents);
  final int cents;

  factory ReportAmount.parse(Object? value) {
    final text = value?.toString() ?? '';
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) throw const FormatException('Invalid report amount');
    final cents = int.parse(match[2]!) * 100 +
        int.parse((match[3] ?? '').padRight(2, '0'));
    return ReportAmount(match[1] == '-' ? -cents : cents);
  }

  @override
  String toString() =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
  String get money => '${cents < 0 ? '-' : ''}\$${ReportAmount(cents.abs())}';
}

@immutable
class SalesReportQuery {
  const SalesReportQuery(
      {this.period = 'today',
      this.year,
      this.month,
      this.dateFrom,
      this.dateTo,
      this.cashierId,
      this.categoryId});
  final String period;
  final int? year;
  final int? month;
  final String? dateFrom;
  final String? dateTo;
  final int? cashierId;
  final int? categoryId;

  Map<String, Object> parameters(int? branchId) => {
        'period': period,
        if (branchId != null) 'branch_id': branchId,
        if (year != null) 'year': year!,
        if (month != null) 'month': month!,
        if (dateFrom != null) 'date_from': dateFrom!,
        if (dateTo != null) 'date_to': dateTo!,
        if (cashierId != null) 'cashier_id': cashierId!,
        if (categoryId != null) 'category_id': categoryId!,
      };

  SalesReportQuery periodSelection(String value,
          {int? year, int? month, String? from, String? to}) =>
      SalesReportQuery(
          period: value,
          year: year,
          month: month,
          dateFrom: from,
          dateTo: to,
          cashierId: cashierId,
          categoryId: categoryId);

  SalesReportQuery filters({int? cashierId, int? categoryId}) =>
      SalesReportQuery(
          period: period,
          year: year,
          month: month,
          dateFrom: dateFrom,
          dateTo: dateTo,
          cashierId: cashierId,
          categoryId: categoryId);
}

class SalesReport {
  SalesReport(Map<String, dynamic> data)
      : meta = Map<String, dynamic>.from(data['meta'] as Map),
        summary = Map<String, dynamic>.from(data['summary'] as Map),
        comparisons = Map<String, dynamic>.from(data['comparisons'] as Map),
        timeline = maps(data['timeline']),
        paymentMethods = maps(data['payment_methods']),
        hourlySales = maps(data['hourly_sales']),
        topProducts = maps(data['top_products']),
        orderTypes = maps(data['order_types']),
        cashFlow = Map<String, dynamic>.from(data['cash_flow'] as Map),
        shifts = Map<String, dynamic>.from(data['shifts'] as Map) {
    for (final key in moneyKeys) {
      amount(key);
    }
    for (final point in timeline) {
      ReportAmount.parse(point['total']);
    }
  }
  static const moneyKeys = [
    'gross_sales',
    'discounts',
    'tax',
    'total_sales',
    'supplemental_sales',
    'refunds',
    'net_sales',
    'average_order_value'
  ];
  final Map<String, dynamic> meta;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> comparisons;
  final List<Map<String, dynamic>> timeline;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> hourlySales;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> orderTypes;
  final Map<String, dynamic> cashFlow;
  final Map<String, dynamic> shifts;
  ReportAmount amount(String key) => ReportAmount.parse(summary[key]);
  String get from => meta['date_from'] as String;
  String get to => meta['date_to'] as String;
  static List<Map<String, dynamic>> maps(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
