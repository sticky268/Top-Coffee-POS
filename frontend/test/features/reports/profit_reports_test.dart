import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/reports/data/report_exporter.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';
import 'package:top_coffee_pos/features/reports/domain/profit_report.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/profit_report_screen.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockProfitRepository extends Mock implements SalesReportsRepository {}

Map<String, dynamic> row({bool incomplete = false}) => {
      'id': 1,
      'name': 'Latte សួស្តី',
      'quantity': 2,
      'lines': 1,
      'gross': '10.00',
      'discounts': '1.00',
      'tax': '0.90',
      'additional': '0.00',
      'refunds': '3.00',
      'refund_tax': '0.30',
      'non_sales_refunds': '0.00',
      'revenue': '6.00',
      'cogs': incomplete ? null : '1.123457',
      'known_cogs': '1.123457',
      'reversed_cogs': '0.000000',
      'gross_profit': incomplete ? null : '4.876543',
      'margin_percent': incomplete ? null : '81.28',
      'margin_change_points': '1.00',
      'unknown_cost_lines': incomplete ? 1 : 0,
      'legacy_category_lines': 1,
      'comparisons': {
        for (final key in profitLabels.keys)
          key: {
            'previous': '1.00',
            'delta': '1.00',
            'percent': '100.00',
            'status': 'comparable'
          }
      },
      'popularity_percent': '100.00',
      'performance': incomplete ? 'cost_missing' : 'star',
    };

ProfitReport fixture({bool incomplete = false}) => ProfitReport({
      'meta': {
        'date_from': '2026-10-19',
        'date_to': '2026-10-19',
        'previous_from': '2026-10-18',
        'previous_to': '2026-10-18',
        'branches': [
          {'id': 21, 'name': 'Riverside', 'timezone': 'Asia/Phnom_Penh'}
        ],
        'basis':
            'Revenue excludes tax. Refunds are proportional allocations to original sale items.',
        'cost_basis': 'Historical costs; missing costs are incomplete.',
        'unsold_basis':
            'Currently available catalogue products, not historical availability.',
        'generated_at': '2026-10-19T02:00:00Z',
        'margin_threshold_percent': '81.28',
        'popularity_threshold_units': '2.00'
      },
      'summary': row(incomplete: incomplete),
      'products': [row(incomplete: incomplete)],
      'categories': [row()],
      'branches': [row()],
      'best_sellers': [row()],
      'slow_sellers': [row()],
      'unsold_products': [
        {'id': 2, 'name': 'No sales product'}
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    registerFallbackValue(const SalesReportQuery());
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  test(
      'costs retain six decimals and exports stay numeric without float conversion',
      () async {
    expect(ReportCost.parse('-0.005000').money, '-\$0.01');
    expect(ReportCost.parse('0.000001').toString(), '0.000001');
    expect(() => ReportCost.parse('1.0000001'), throwsFormatException);
    final rows = profitReportRows(fixture());
    final archive = ZipDecoder().decodeBytes(ReportExporter.xlsx(rows));
    final sheet =
        utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content);
    expect(sheet, contains('t="n"><v>1.123457</v>'));
    expect(sheet, contains('t="n"><v>4.876543</v>'));
    expect(sheet, contains('Riverside'));
    expect(ReportExporter.csv(profitReportRows(fixture(incomplete: true))),
        contains('Incomplete'));
    final directory = Directory('build/report-exports')
      ..createSync(recursive: true);
    for (final format in [ReportExportFormat.xlsx, ReportExportFormat.pdf]) {
      final file = await ReportExporter.buildRows(
          format == ReportExportFormat.pdf
              ? profitReportPdfRows(fixture())
              : rows,
          'profit-exact',
          format,
          title: 'Profitability report',
          columnFlex: [4, 3, 3, 3]);
      File('${directory.path}/${file.name}').writeAsBytesSync(file.bytes);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'profit overview fits phone at text scale $scale and opens exact source filters',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockProfitRepository();
      when(() => repository.profit(any(), 21))
          .thenAnswer((_) async => fixture(incomplete: true));
      when(() =>
          repository.profitDetails(any(), 21,
              productId: any(named: 'productId'),
              category: any(named: 'category'),
              page: any(named: 'page'))).thenAnswer((_) async => {
            'rows': [
              row()
                ..addAll({
                  'order_id': 7,
                  'order_number': 7,
                  'branch_name': 'Riverside',
                  'occurred_at_local': '2026-10-19 08:00:00 +07:00',
                  'category_name': 'Coffee'
                })
            ],
            'total': 1,
            'page': 1,
            'per_page': 50
          });
      final key = GlobalKey();
      const query = SalesReportQuery(
          period: 'custom',
          dateFrom: '2026-10-19',
          dateTo: '2026-10-19',
          cashierId: 5);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            salesReportsRepositoryProvider.overrideWithValue(repository)
          ],
          child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(360, 800),
                      textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                      key: key,
                      child: const ProfitReportScreen(
                          query: query, branchId: 21))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await savePreview(tester, key, 'profit-report-phone-$scale.png');
      final tile = find.text('Revenue excluding tax');
      await tester.scrollUntilVisible(tile, 250);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Order 7 · Latte សួស្តី'), findsOneWidget);
      expect(find.textContaining('Riverside · 2026-10-19'), findsOneWidget);
      final captured = verify(() => repository.profitDetails(captureAny(), 21,
          productId: null,
          category: null,
          page: 1)).captured.single as SalesReportQuery;
      expect(captured.dateFrom, '2026-10-19');
      expect(captured.cashierId, 5);
      expect(tester.takeException(), isNull);
    });
  }
}
