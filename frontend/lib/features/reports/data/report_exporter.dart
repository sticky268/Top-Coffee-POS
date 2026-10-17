import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/reports_models.dart';

enum ReportExportFormat { csv, xlsx, pdf }

class ReportExportFile {
  const ReportExportFile(this.name, this.mimeType, this.bytes);
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Exports the loaded, server-authorized report without inventing rows.
class ReportExporter {
  static List<List<Object>> rows(ReportsData report, String branch) => [
    ['Top Coffee POS sales report'],
    ['Branch', branch],
    ['From', report.summary.dateFrom.toIso8601String().split('T').first],
    ['To', report.summary.dateTo.toIso8601String().split('T').first],
    ['Timezone', report.summary.timezone],
    ['Date basis', 'Completed sales; legacy records use creation date'],
    ['Order sales before adjustments', report.summary.totalSales],
    ['Additional charges', report.summary.supplementalSales],
    ['Refunds on selected sales', report.summary.refunds],
    ['Net after adjustments', report.summary.netSales],
    ['Adjustments', 'Current ledger for selected sales; Daily Operations reports event-date cash flow'],
    ['Orders', report.summary.totalOrders],
    ['Average order value', report.summary.averageOrderValue],
    [],
    ['Daily sales', 'Total'],
    for (final row in report.salesOverview)
      [row.date.toIso8601String().split('T').first, row.total],
    [],
    ['Hourly sales', 'Total'],
    for (final row in report.hourlySales) [row.hour, row.total],
    [],
    ['Payment method (net)', 'Total', 'Count'],
    for (final row in report.paymentMethods) [row.method, row.total, row.count],
    [],
    ['Order type', 'Total', 'Count'],
    for (final row in report.orderTypes) [row.type, row.total, row.count],
    [],
    ['Top products (before order discounts)', 'Sales', 'Quantity'],
    for (final row in report.topProducts)
      [row.productName, row.salesTotal, row.quantitySold],
  ];

  static String csv(List<List<Object>> rows) {
    String cell(Object value) {
      var text = value.toString();
      // CSV quoting does not prevent spreadsheet formula execution.
      if (value is! num && RegExp(r'^[\s]*[=+\-@]').hasMatch(text)) {
        text = "'$text";
      }
      return ['"', text.replaceAll('"', '""'), '"'].join();
    }
    return ['\uFEFF', rows.map((row) => row.map(cell).join(',')).join('\r\n'), '\r\n'].join();
  }

  static String _xml(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Uint8List xlsx(List<List<Object>> rows) {
    final archive = Archive();
    void add(String path, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }
    const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const rels = 'http://schemas.openxmlformats.org/package/2006/relationships';
    const office = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>');
    add('_rels/.rels', '<Relationships xmlns="$rels">'
      '<Relationship Id="rId1" Type="$office/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>');
    add('xl/workbook.xml', '<workbook xmlns="$main" xmlns:r="$office">'
      '<sheets><sheet name="Sales report" sheetId="1" r:id="rId1"/></sheets></workbook>');
    add('xl/_rels/workbook.xml.rels', '<Relationships xmlns="$rels">'
      '<Relationship Id="rId1" Type="$office/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>');
    final data = StringBuffer('<worksheet xmlns="$main"><cols>'
      '<col min="1" max="1" width="48" customWidth="1"/>'
      '<col min="2" max="3" width="24" customWidth="1"/>'
      '</cols><sheetData>');
    for (var r = 0; r < rows.length; r++) {
      final rowNumber = r + 1;
      data.write('<row r="$rowNumber">');
      for (var c = 0; c < rows[r].length; c++) {
        final value = rows[r][c];
        final ref = '${String.fromCharCode(65 + c)}$rowNumber';
        if (value is num) {
          data.write('<c r="$ref" t="n"><v>$value</v></c>');
        } else {
          data.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(value.toString())}</t></is></c>');
        }
      }
      data.write('</row>');
    }
    data.write('</sheetData></worksheet>');
    add('xl/worksheets/sheet1.xml', data.toString());
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Future<ReportExportFile> build(ReportsData report, String branch,
      ReportExportFormat format) async {
    final data = rows(report, branch);
    final start = report.summary.dateFrom.toIso8601String().split('T').first;
    final end = report.summary.dateTo.toIso8601String().split('T').first;
    final name = 'top-coffee-sales-$start-$end';
    switch (format) {
      case ReportExportFormat.csv:
        return ReportExportFile('$name.csv', 'text/csv',
            Uint8List.fromList(utf8.encode(csv(data))));
      case ReportExportFormat.xlsx:
        return ReportExportFile('$name.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', xlsx(data));
      case ReportExportFormat.pdf:
        final document = pw.Document();
        final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          maxPages: 100,
          theme: pw.ThemeData.withFont(base: font, bold: font),
          header: (_) => pw.Text('Top Coffee POS - Sales report'),
          footer: (context) => pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}')),
          build: (_) => [pw.TableHelper.fromTextArray(
            data: data.map((row) => List.generate(3,
              (i) => i < row.length ? row[i].toString() : '')).toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          )],
        ));
        return ReportExportFile('$name.pdf', 'application/pdf', await document.save());
    }
  }
}
