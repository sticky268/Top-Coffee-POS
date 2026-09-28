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

  static Future<ReceiptSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    return ReceiptSettings(
      businessName:
          prefs.getString('receipt_business_name') ??
              defaultBusinessName,
      branchName:
          prefs.getString('receipt_branch_name') ??
              defaultBranchName,
      logoPosition:
          prefs.getString('receipt_logo_position') ?? 'Center',
      logoSize:
          prefs.getString('receipt_logo_size') ?? 'Medium',
      fontStyle:
          prefs.getString('receipt_font_style') ?? 'Default',
      bodyFontSize:
          prefs.getString('receipt_body_font_size') ?? 'Medium',
      businessFontSize:
          prefs.getString('receipt_business_font_size') ?? 'Large',
      footerFontSize:
          prefs.getString('receipt_footer_font_size') ?? 'Medium',
      boldBusinessName:
          prefs.getBool('receipt_bold_business_name') ?? true,
      boldTotal:
          prefs.getBool('receipt_bold_total') ?? true,
      boldFooter:
          prefs.getBool('receipt_bold_footer') ?? true,
      showOrderNumber:
          prefs.getBool('receipt_show_order_number') ?? true,
      showDateTime:
          prefs.getBool('receipt_show_date_time') ?? true,
      showCashier:
          prefs.getBool('receipt_show_cashier') ?? true,
      showTable:
          prefs.getBool('receipt_show_table') ?? true,
      showOrderType:
          prefs.getBool('receipt_show_order_type') ?? true,
      showItemName:
          prefs.getBool('receipt_show_item_name') ?? true,
      showQuantity:
          prefs.getBool('receipt_show_quantity') ?? true,
      showUnitPrice:
          prefs.getBool('receipt_show_unit_price') ?? true,
      showLineTotal:
          prefs.getBool('receipt_show_line_total') ?? true,
      showPaymentMethod:
          prefs.getBool('receipt_show_payment_method') ?? true,
      showTendered:
          prefs.getBool('receipt_show_tendered') ?? true,
      showChange:
          prefs.getBool('receipt_show_change') ?? true,
      showSplitPayments:
          prefs.getBool('receipt_show_split_payments') ?? true,
      footer:
          prefs.getString('receipt_footer') ?? defaultFooter,
      printerEnabled:
          prefs.getBool('receipt_printer_enabled') ?? true,
      printerIpAddress:
          prefs.getString('receipt_printer_ip') ??
              defaultPrinterIpAddress,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'receipt_business_name',
      businessName,
    );
    await prefs.setString(
      'receipt_branch_name',
      branchName,
    );
    await prefs.setString(
      'receipt_logo_position',
      logoPosition,
    );
    await prefs.setString(
      'receipt_logo_size',
      logoSize,
    );
    await prefs.setString(
      'receipt_font_style',
      fontStyle,
    );
    await prefs.setString(
      'receipt_body_font_size',
      bodyFontSize,
    );
    await prefs.setString(
      'receipt_business_font_size',
      businessFontSize,
    );
    await prefs.setString(
      'receipt_footer_font_size',
      footerFontSize,
    );

    await prefs.setBool(
      'receipt_bold_business_name',
      boldBusinessName,
    );
    await prefs.setBool(
      'receipt_bold_total',
      boldTotal,
    );
    await prefs.setBool(
      'receipt_bold_footer',
      boldFooter,
    );

    await prefs.setBool(
      'receipt_show_order_number',
      showOrderNumber,
    );
    await prefs.setBool(
      'receipt_show_date_time',
      showDateTime,
    );
    await prefs.setBool(
      'receipt_show_cashier',
      showCashier,
    );
    await prefs.setBool(
      'receipt_show_table',
      showTable,
    );
    await prefs.setBool(
      'receipt_show_order_type',
      showOrderType,
    );

    await prefs.setBool(
      'receipt_show_item_name',
      showItemName,
    );
    await prefs.setBool(
      'receipt_show_quantity',
      showQuantity,
    );
    await prefs.setBool(
      'receipt_show_unit_price',
      showUnitPrice,
    );
    await prefs.setBool(
      'receipt_show_line_total',
      showLineTotal,
    );

    await prefs.setBool(
      'receipt_show_payment_method',
      showPaymentMethod,
    );
    await prefs.setBool(
      'receipt_show_tendered',
      showTendered,
    );
    await prefs.setBool(
      'receipt_show_change',
      showChange,
    );
    await prefs.setBool(
      'receipt_show_split_payments',
      showSplitPayments,
    );

    await prefs.setString(
      'receipt_footer',
      footer,
    );

    await prefs.setBool(
      'receipt_printer_enabled',
      printerEnabled,
    );
    await prefs.setString(
      'receipt_printer_ip',
      printerIpAddress,
    );
  }
}