import 'package:shared_preferences/shared_preferences.dart';

class ReceiptSettings {
  const ReceiptSettings({
    required this.businessName,
    required this.branchName,
    required this.logoPosition,
    required this.logoSize,
    required this.fontStyle,
    required this.bodyFontSize,
    required this.businessFontSize,
    required this.footerFontSize,
    required this.boldBusinessName,
    required this.boldTotal,
    required this.boldFooter,
    required this.showOrderNumber,
    required this.showDateTime,
    required this.showCashier,
    required this.showTable,
    required this.showOrderType,
    required this.showItemName,
    required this.showQuantity,
    required this.showUnitPrice,
    required this.showLineTotal,
    required this.showPaymentMethod,
    required this.showTendered,
    required this.showChange,
    required this.showSplitPayments,
    required this.footer,
    required this.printerEnabled,
    required this.printerIpAddress,
  });

  final String businessName;
  final String branchName;
  final String logoPosition;
  final String logoSize;
  final String fontStyle;
  final String bodyFontSize;
  final String businessFontSize;
  final String footerFontSize;

  final bool boldBusinessName;
  final bool boldTotal;
  final bool boldFooter;

  final bool showOrderNumber;
  final bool showDateTime;
  final bool showCashier;
  final bool showTable;
  final bool showOrderType;

  final bool showItemName;
  final bool showQuantity;
  final bool showUnitPrice;
  final bool showLineTotal;

  final bool showPaymentMethod;
  final bool showTendered;
  final bool showChange;
  final bool showSplitPayments;

  final String footer;

  final bool printerEnabled;
  final String printerIpAddress;

  static const String defaultPrinterIpAddress = '192.168.1.111';

  static const String defaultBusinessName = 'TOP COFFEE';
  static const String defaultBranchName = 'Phnom Penh Branch';
  static const String defaultFooter =
      'Thank you for visiting Top Coffee!';

  static String _key(String base, String? branchKey) {
    final scope = branchKey?.trim();
    return scope == null || scope.isEmpty ? base : '${base}_branch_${scope.toLowerCase()}';
  }

  static Future<ReceiptSettings> load({
    String? branchKey,
    String? branchNameFallback,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    return ReceiptSettings(
      businessName:
          prefs.getString(_key('receipt_business_name', branchKey)) ??
              defaultBusinessName,
      branchName:
          prefs.getString(_key('receipt_branch_name', branchKey)) ??
              branchNameFallback ??
              defaultBranchName,
      logoPosition:
          prefs.getString(_key('receipt_logo_position', branchKey)) ?? 'Center',
      logoSize:
          prefs.getString(_key('receipt_logo_size', branchKey)) ?? 'Medium',
      fontStyle:
          prefs.getString(_key('receipt_font_style', branchKey)) ?? 'Default',
      bodyFontSize:
          prefs.getString(_key('receipt_body_font_size', branchKey)) ?? 'Medium',
      businessFontSize:
          prefs.getString(_key('receipt_business_font_size', branchKey)) ?? 'Large',
      footerFontSize:
          prefs.getString(_key('receipt_footer_font_size', branchKey)) ?? 'Medium',
      boldBusinessName:
          prefs.getBool(_key('receipt_bold_business_name', branchKey)) ?? true,
      boldTotal:
          prefs.getBool(_key('receipt_bold_total', branchKey)) ?? true,
      boldFooter:
          prefs.getBool(_key('receipt_bold_footer', branchKey)) ?? true,
      showOrderNumber:
          prefs.getBool(_key('receipt_show_order_number', branchKey)) ?? true,
      showDateTime:
          prefs.getBool(_key('receipt_show_date_time', branchKey)) ?? true,
      showCashier:
          prefs.getBool(_key('receipt_show_cashier', branchKey)) ?? true,
      showTable:
          prefs.getBool(_key('receipt_show_table', branchKey)) ?? true,
      showOrderType:
          prefs.getBool(_key('receipt_show_order_type', branchKey)) ?? true,
      showItemName:
          prefs.getBool(_key('receipt_show_item_name', branchKey)) ?? true,
      showQuantity:
          prefs.getBool(_key('receipt_show_quantity', branchKey)) ?? true,
      showUnitPrice:
          prefs.getBool(_key('receipt_show_unit_price', branchKey)) ?? true,
      showLineTotal:
          prefs.getBool(_key('receipt_show_line_total', branchKey)) ?? true,
      showPaymentMethod:
          prefs.getBool(_key('receipt_show_payment_method', branchKey)) ?? true,
      showTendered:
          prefs.getBool(_key('receipt_show_tendered', branchKey)) ?? true,
      showChange:
          prefs.getBool(_key('receipt_show_change', branchKey)) ?? true,
      showSplitPayments:
          prefs.getBool(_key('receipt_show_split_payments', branchKey)) ?? true,
      footer:
          prefs.getString(_key('receipt_footer', branchKey)) ?? defaultFooter,
      printerEnabled:
          prefs.getBool(_key('receipt_printer_enabled', branchKey)) ?? true,
      printerIpAddress:
          prefs.getString(_key('receipt_printer_ip', branchKey)) ??
              defaultPrinterIpAddress,
    );
  }

  Future<void> save({String? branchKey}) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key('receipt_business_name', branchKey),
      businessName,
    );
    await prefs.setString(
      _key('receipt_branch_name', branchKey),
      branchName,
    );
    await prefs.setString(
      _key('receipt_logo_position', branchKey),
      logoPosition,
    );
    await prefs.setString(
      _key('receipt_logo_size', branchKey),
      logoSize,
    );
    await prefs.setString(
      _key('receipt_font_style', branchKey),
      fontStyle,
    );
    await prefs.setString(
      _key('receipt_body_font_size', branchKey),
      bodyFontSize,
    );
    await prefs.setString(
      _key('receipt_business_font_size', branchKey),
      businessFontSize,
    );
    await prefs.setString(
      _key('receipt_footer_font_size', branchKey),
      footerFontSize,
    );

    await prefs.setBool(
      _key('receipt_bold_business_name', branchKey),
      boldBusinessName,
    );
    await prefs.setBool(
      _key('receipt_bold_total', branchKey),
      boldTotal,
    );
    await prefs.setBool(
      _key('receipt_bold_footer', branchKey),
      boldFooter,
    );

    await prefs.setBool(
      _key('receipt_show_order_number', branchKey),
      showOrderNumber,
    );
    await prefs.setBool(
      _key('receipt_show_date_time', branchKey),
      showDateTime,
    );
    await prefs.setBool(
      _key('receipt_show_cashier', branchKey),
      showCashier,
    );
    await prefs.setBool(
      _key('receipt_show_table', branchKey),
      showTable,
    );
    await prefs.setBool(
      _key('receipt_show_order_type', branchKey),
      showOrderType,
    );

    await prefs.setBool(
      _key('receipt_show_item_name', branchKey),
      showItemName,
    );
    await prefs.setBool(
      _key('receipt_show_quantity', branchKey),
      showQuantity,
    );
    await prefs.setBool(
      _key('receipt_show_unit_price', branchKey),
      showUnitPrice,
    );
    await prefs.setBool(
      _key('receipt_show_line_total', branchKey),
      showLineTotal,
    );

    await prefs.setBool(
      _key('receipt_show_payment_method', branchKey),
      showPaymentMethod,
    );
    await prefs.setBool(
      _key('receipt_show_tendered', branchKey),
      showTendered,
    );
    await prefs.setBool(
      _key('receipt_show_change', branchKey),
      showChange,
    );
    await prefs.setBool(
      _key('receipt_show_split_payments', branchKey),
      showSplitPayments,
    );

    await prefs.setString(
      _key('receipt_footer', branchKey),
      footer,
    );

    await prefs.setBool(
      _key('receipt_printer_enabled', branchKey),
      printerEnabled,
    );
    await prefs.setString(
      _key('receipt_printer_ip', branchKey),
      printerIpAddress,
    );
  }
}