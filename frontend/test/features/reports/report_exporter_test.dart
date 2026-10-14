import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/reports/data/report_exporter.dart';
import 'package:top_coffee_pos/features/reports/domain/reports_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = ReportsData(
    summary: ReportSummary(dateFrom: DateTime(2026, 10, 14), dateTo: DateTime(2026, 10, 14),
      totalSales: 12.5, totalOrders: 1, averageOrderValue: 12.5),
    salesOverview: [ReportSalesPoint(date: DateTime(2026, 10, 14), total: 12.5)],
    hourlySales: const [], paymentMethods: const [], orderTypes: const [],
    topProducts: const [ReportTopProduct(productId: 1, productName: '=1+1, "Latte"',
      quantitySold: 1, salesTotal: 12.5)],
  );

  test('CSV escapes names and neutralizes formula text while preserving numbers', () {
    final csv = ReportExporter.csv(ReportExporter.rows(report, 'Cafe'));
    expect(csv, contains('"\u0027=1+1, ""Latte"""'));
    expect(csv, contains('"12.5"'));
    expect(csv, startsWith('\uFEFF'));
  });

  test('Excel is an OOXML workbook with numeric amounts and literal text', () async {
    final file = await ReportExporter.build(report, 'Cafe & Coffee', ReportExportFormat.xlsx);
    final archive = ZipDecoder().decodeBytes(file.bytes);
    expect(archive.findFile('[Content_Types].xml'), isNotNull);
    expect(archive.findFile('xl/workbook.xml'), isNotNull);
    final sheet = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content);
    expect(sheet, contains('t="n"><v>12.5</v>'));
    expect(sheet, contains('Cafe &amp; Coffee'));
    expect(sheet, contains('=1+1, &quot;Latte&quot;'));
    expect(sheet, isNot(contains('<f>')));
    // Keep a fixture for independent Excel-reader validation in CI artifacts.
    final directory = Directory('build/report-exports')..createSync(recursive: true);
    File('${directory.path}/sales.xlsx').writeAsBytesSync(file.bytes);
  });

  test('PDF export produces a complete PDF with the real report', () async {
    final file = await ReportExporter.build(report, 'Cafe', ReportExportFormat.pdf);
    expect(ascii.decode(file.bytes.take(5).toList()), '%PDF-');
    expect(file.bytes.length, greaterThan(1000));
    final directory = Directory('build/report-exports')..createSync(recursive: true);
    File('${directory.path}/sales.pdf').writeAsBytesSync(file.bytes);
  });
}
