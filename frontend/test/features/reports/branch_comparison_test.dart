import 'dart:async';
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
import 'package:top_coffee_pos/features/reports/domain/branch_comparison.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/branch_comparison_screen.dart';
import 'profit_reports_test.dart' show fixture, row;
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockBranchRepository extends Mock implements SalesReportsRepository {}

Map<String, dynamic> branchesFixture() => {
      'meta': {
        ...fixture().meta,
        'comparison_basis':
            'All accessible branches; growth is not trading-day-normalised.'
      },
      'summary': {...row(), 'name': 'All selected sales'},
      'branches': [
        {
          ...row(),
          'id': 21,
          'name': '=Riverside',
          'timezone': 'Asia/Phnom_Penh',
          'revenue_rank': 1,
          'revenue_share_percent': '100.00'
        },
        {
          ...row(incomplete: true),
          'id': 22,
          'name': 'Airport',
          'timezone': 'Asia/Phnom_Penh',
          'revenue_rank': 2,
          'revenue_share_percent': '0.00'
        },
      ],
    };

const query = SalesReportQuery(
    period: 'custom',
    dateFrom: '2026-10-19',
    dateTo: '2026-10-19',
    comparisonFrom: '2026-10-18',
    comparisonTo: '2026-10-18',
    cashierId: 5,
    categoryId: 6);

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
      'branch exports preserve exact costs, comparisons and literal branch names',
      () async {
    final report = BranchComparison(branchesFixture());
    final rows = branchComparisonRows(report);
    final csv = ReportExporter.csv(rows);
    expect(csv, contains("'=Riverside"));
    expect(csv, contains('Unavailable'));
    final xml = utf8.decode(ZipDecoder()
        .decodeBytes(ReportExporter.xlsx(rows))
        .findFile('xl/worksheets/sheet1.xml')!
        .content);
    expect(xml, contains('t="n"><v>1.123457</v>'));
    expect(xml, contains('t="n"><v>4.876543</v>'));
    expect(
        branchChange(row(incomplete: true), 'cogs'), contains('unavailable'));
    final directory = Directory('build/report-exports')
      ..createSync(recursive: true);
    for (final format in [ReportExportFormat.xlsx, ReportExportFormat.pdf]) {
      final file = await ReportExporter.buildRows(
          branchComparisonRows(report, pdf: format == ReportExportFormat.pdf),
          'branches-exact',
          format,
          title: 'Branch comparison',
          columnFlex: [4, 3, 3, 3],
          notes: format == ReportExportFormat.pdf ? report.basis : null);
      File('${directory.path}/${file.name}').writeAsBytesSync(file.bytes);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'branch phone layout $scale and scoped drill-down retain pinned filters',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockBranchRepository();
      when(() => repository.branchComparison(any(), null))
          .thenAnswer((_) async => branchesFixture());
      when(() => repository.profitDetails(any(), 21, page: 1))
          .thenAnswer((_) async => {
                'rows': [
                  {
                    ...row(),
                    'order_number': 'TEST-21',
                    'order_id': 1,
                    'branch_name': '=Riverside',
                    'occurred_at_local': '2026-10-19 08:00:00 +07:00',
                    'category_name': 'Coffee'
                  }
                ],
                'page': 1,
                'total': 1,
              });
      final key = GlobalKey();
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
                      child: const BranchComparisonScreen(query: query))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await savePreview(tester, key, 'branches-overview-$scale');
      final branch = find.byKey(const ValueKey('branch-21'));
      await tester.scrollUntilVisible(branch, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final title = find.text('=Riverside');
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      scroll.jumpTo((scroll.pixels + tester.getCenter(title).dy - 300)
          .clamp(scroll.minScrollExtent, scroll.maxScrollExtent));
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      final revenue = find.descendant(
          of: branch,
          matching: find.widgetWithText(ListTile, 'Revenue excluding tax'));
      await tester.scrollUntilVisible(revenue, 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      scroll.jumpTo((scroll.pixels + tester.getCenter(revenue).dy - 400)
          .clamp(scroll.minScrollExtent, scroll.maxScrollExtent));
      await tester.pumpAndSettle();
      expect(revenue.hitTestable(), findsOneWidget);
      await savePreview(tester, key, 'branches-expanded-$scale');
      await tester.tap(revenue);
      await tester.pumpAndSettle();
      expect(find.textContaining('TEST-21'), findsOneWidget);
      final sent =
          verify(() => repository.profitDetails(captureAny(), 21, page: 1))
              .captured
              .single as SalesReportQuery;
      expect(sent.parameters(21), query.parameters(21));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('comparison loading, failure and retry show fresh data',
      (tester) async {
    final repository = MockBranchRepository();
    final pending = Completer<Map<String, dynamic>>();
    when(() => repository.branchComparison(any(), null))
        .thenAnswer((_) => pending.future);
    await tester.pumpWidget(ProviderScope(overrides: [
      salesReportsRepositoryProvider.overrideWithValue(repository)
    ], child: const MaterialApp(home: BranchComparisonScreen(query: query))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    when(() => repository.branchComparison(any(), null))
        .thenAnswer((_) async => branchesFixture());
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('All accessible branches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
