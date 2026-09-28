import 'package:flutter/foundation.dart';

@immutable
class ReportSummary {
  const ReportSummary({
    required this.dateFrom,
    required this.dateTo,
    required this.totalSales,
    required this.totalOrders,
    required this.averageOrderValue,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final double totalSales;
  final int totalOrders;
  final double averageOrderValue;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      dateFrom: DateTime.parse(json['date_from'] as String),
      dateTo: DateTime.parse(json['date_to'] as String),
      totalSales: _toDouble(json['total_sales']),
      totalOrders: _toInt(json['total_orders']),
      averageOrderValue: _toDouble(json['average_order_value']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportSalesPoint {
  const ReportSalesPoint({
    required this.date,
    required this.total,
  });

  final DateTime date;
  final double total;

  factory ReportSalesPoint.fromJson(Map<String, dynamic> json) {
    return ReportSalesPoint(
      date: DateTime.parse(json['date'] as String),
      total: _toDouble(json['total']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportHourlySalesPoint {
  const ReportHourlySalesPoint({
    required this.hour,
    required this.total,
  });

  final String hour;
  final double total;

  factory ReportHourlySalesPoint.fromJson(Map<String, dynamic> json) {
    return ReportHourlySalesPoint(
      hour: json['hour']?.toString() ?? '',
      total: _toDouble(json['total']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportPaymentMethod {
  const ReportPaymentMethod({
    required this.method,
    required this.total,
    required this.count,
  });

  final String method;
  final double total;
  final int count;

  factory ReportPaymentMethod.fromJson(Map<String, dynamic> json) {
    return ReportPaymentMethod(
      method: json['method']?.toString() ?? '',
      total: _toDouble(json['total']),
      count: _toInt(json['count']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportOrderType {
  const ReportOrderType({
    required this.type,
    required this.count,
    required this.total,
  });

  final String type;
  final int count;
  final double total;

  factory ReportOrderType.fromJson(Map<String, dynamic> json) {
    return ReportOrderType(
      type: json['type']?.toString() ?? '',
      count: _toInt(json['count']),
      total: _toDouble(json['total']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportTopProduct {
  const ReportTopProduct({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.salesTotal,
  });

  final int productId;
  final String productName;
  final int quantitySold;
  final double salesTotal;

  factory ReportTopProduct.fromJson(Map<String, dynamic> json) {
    return ReportTopProduct(
      productId: _toInt(json['product_id']),
      productName: json['product_name']?.toString() ?? '',
      quantitySold: _toInt(json['quantity_sold']),
      salesTotal: _toDouble(json['sales_total']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

@immutable
class ReportsData {
  const ReportsData({
    required this.summary,
    required this.salesOverview,
    required this.hourlySales,
    required this.paymentMethods,
    required this.orderTypes,
    required this.topProducts,
  });

  final ReportSummary summary;
  final List<ReportSalesPoint> salesOverview;
  final List<ReportHourlySalesPoint> hourlySales;
  final List<ReportPaymentMethod> paymentMethods;
  final List<ReportOrderType> orderTypes;
  final List<ReportTopProduct> topProducts;

  factory ReportsData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final salesOverview = json['sales_overview'];
    final hourlySales = json['hourly_sales'];
    final paymentMethods = json['payment_methods'];
    final orderTypes = json['order_types'];
    final topProducts = json['top_products'];

    if (summary is! Map) {
      throw const FormatException('Invalid report summary response');
    }

    if (salesOverview is! List) {
      throw const FormatException('Invalid report sales overview response');
    }

    if (hourlySales is! List) {
      throw const FormatException('Invalid report hourly sales response');
    }

    if (paymentMethods is! List) {
      throw const FormatException('Invalid report payment methods response');
    }

    if (orderTypes is! List) {
      throw const FormatException('Invalid report order types response');
    }

    if (topProducts is! List) {
      throw const FormatException('Invalid report top products response');
    }

    return ReportsData(
      summary: ReportSummary.fromJson(
        Map<String, dynamic>.from(summary),
      ),
      salesOverview: salesOverview
          .map(
            (item) => ReportSalesPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      hourlySales: hourlySales
          .map(
            (item) => ReportHourlySalesPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      paymentMethods: paymentMethods
          .map(
            (item) => ReportPaymentMethod.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      orderTypes: orderTypes
          .map(
            (item) => ReportOrderType.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      topProducts: topProducts
          .map(
            (item) => ReportTopProduct.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
