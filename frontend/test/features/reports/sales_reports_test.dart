import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/reports/application/sales_reports_controller.dart';
import 'package:top_coffee_pos/features/reports/data/report_exporter.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/reports_screen.dart';
import 'sales_report_fixture.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockSalesRepository extends Mock implements SalesReportsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    registerFallbackValue(const SalesReportQuery());
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  test('report money preserves large values and rejects malformed values', () {
    expect(
      ReportAmount.parse('90071992547409.91').toString(),
      '90071992547409.91',
    );
    expect(ReportAmount.parse('-0.10').money, '-\$0.10');
    expect(ReportAmount.parse('1.2').toString(), '1.20');
    expect(() => ReportAmount.parse(null), throwsFormatException);
    expect(() => ReportAmount.parse('1.234'), throwsFormatException);
  });

  test('exact money remains a numeric Excel cell and comparisons export', () {
    final report = salesReportFixture();
    final rows = salesReportRows(report);
    final bytes = ReportExporter.xlsx(rows);
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    expect(sheet, contains('t="n"><v>1234567.89</v>'));
    expect(sheet, contains('Asia/Phnom_Penh'));
    expect(sheet, contains('Change vs previous period'));
    expect(
      ReportExporter.csv([
        [const ReportAmount(-10)],
      ]),
      contains('"-0.10"'),
    );
  });

  test(
    'four-column PDF and exact Excel exports remain readable by external tools',
    () async {
      final rows = <List<Object>>[
        ['Top Coffee POS sales report'],
        ['Branch', 'Riverside'],
        ['Payment method', 'Collected', 'Refunds', 'Net'],
        [
          'cash',
          const ReportAmount(1001),
          const ReportAmount(200),
          const ReportAmount(801),
        ],
        ['Negative adjustment', const ReportAmount(-10)],
      ];
      final directory = Directory('build/report-exports')
        ..createSync(recursive: true);
      for (final format in [ReportExportFormat.xlsx, ReportExportFormat.pdf]) {
        final file = await ReportExporter.buildRows(
          rows,
          'sales-exact',
          format,
        );
        File('${directory.path}/${file.name}').writeAsBytesSync(file.bytes);
      }
    },
  );

  ProviderContainer container(MockSalesRepository repository) =>
      ProviderContainer(
        overrides: [
          salesReportsRepositoryProvider.overrideWithValue(repository),
          currentBranchProvider.overrideWith(
            (ref) => CurrentBranchNotifier(ref, listenToAuth: false)
              ..selectBranch(
                const BranchSummary(id: 21, name: 'Riverside', code: 'PP-01'),
              ),
          ),
        ],
      );

  test(
    'controller sends server presets and ignores late previous-branch results',
    () async {
      final repository = MockSalesRepository();
      final first = Completer<SalesReport>();
      when(() => repository.load(any(), 21)).thenAnswer((_) => first.future);
      when(
        () => repository.load(any(), 22),
      ).thenAnswer((_) async => salesReportFixture(total: '22.00'));
      final scope = container(repository);
      addTearDown(scope.dispose);
      final controller = scope.read(salesReportsControllerProvider.notifier);
      scope.read(currentBranchProvider.notifier).selectBranch(
            const BranchSummary(id: 22, name: 'Second', code: 'PP-02'),
          );
      await Future<void>.delayed(Duration.zero);
      first.complete(salesReportFixture(total: '21.00'));
      await controller.initialization;
      final report = scope.read(salesReportsControllerProvider).requireValue;
      expect(report.amount('total_sales').toString(), '22.00');
      final sent = verify(() => repository.load(captureAny(), 21))
          .captured
          .single as SalesReportQuery;
      expect(sent.period, 'today');
      expect(sent.parameters(21).containsKey('date_from'), isFalse);
    },
  );

  testWidgets(
    'year opens all months, month opens daily rows, KPI opens source orders',
    (tester) async {
      final repository = MockSalesRepository();
      when(() => repository.load(any(), any())).thenAnswer((invocation) async {
        final query = invocation.positionalArguments[0] as SalesReportQuery;
        return salesReportFixture(period: query.period);
      });
      when(
        () => repository.details(
          any(),
          any(),
          kind: any(named: 'kind'),
          metric: any(named: 'metric'),
          method: any(named: 'method'),
          page: any(named: 'page'),
        ),
      ).thenAnswer(
        (_) async => {
          'total': 1,
          'rows': [
            {
              'order_id': 42,
              'order_number': 7,
              'branch_id': 21,
              'branch_name': 'Riverside',
              'timezone': 'Asia/Phnom_Penh',
              'occurred_at_local': '2026-10-19 08:00:00 +07:00',
              'amount': '12.34',
              'gross_sales': '12.34',
              'tax': '0.00',
              'discounts': '0.00',
              'occurred_at': '2026-10-19 01:00:00',
            },
          ],
        },
      );
      final scope = container(repository);
      addTearDown(scope.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(key: preview, child: const ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await savePreview(tester, preview, 'sales-report-overview-phone');
      expect(find.text('Gross sales'), findsNothing);
      expect(find.text('Net sales').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Dates & filters'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Browse all 12 months').hitTestable(),
        150,
      );
      await tester.tap(find.text('Browse all 12 months'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Monthly history · 2026'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly history · 2026'));
      await tester.pumpAndSettle();
      await savePreview(tester, preview, 'sales-report-month-history-phone');
      await tester.scrollUntilVisible(find.text('February').hitTestable(), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('February').hitTestable());
      await tester.pumpAndSettle();
      expect(
        scope.read(salesReportsControllerProvider.notifier).query.month,
        2,
      );
      await tester.scrollUntilVisible(
        find.text('Net sales').hitTestable(),
        -200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Net sales').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Report source records'), findsOneWidget);
      expect(find.text('Order 7 · Riverside'), findsOneWidget);
      final source = verify(
        () => repository.details(
          captureAny(),
          any(),
          kind: 'orders',
          metric: 'net_sales',
          method: null,
          page: 1,
        ),
      ).captured.single as SalesReportQuery;
      expect(source.period, 'custom');
      expect(source.dateFrom, '2026-10-19');
      expect(source.dateTo, '2026-10-19');
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('summary keeps key totals clear at $size', (tester) async {
      final repository = MockSalesRepository();
      when(() => repository.load(any(), any()))
          .thenAnswer((_) async => salesReportFixture());
      final scope = container(repository);
      addTearDown(scope.dispose);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(key: preview, child: const ReportsScreen())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Net sales').hitTestable(), findsOneWidget);
      expect(find.text('Paid orders').hitTestable(), findsOneWidget);
      expect(find.text('Average order').hitTestable(), findsOneWidget);
      expect(find.text('Refunds').hitTestable(), findsOneWidget);
      expect(find.text(r'$1,234,567.89'), findsWidgets);
      expect(find.text('Gross sales'), findsNothing);
      expect(find.text('Cashier'), findsNothing);
      await savePreview(tester, preview, 'sales-summary-${size.width.toInt()}');
      await tester.scrollUntilVisible(find.text('Sales breakdown'), 200);
      await tester.tap(find.text('Sales breakdown'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gross sales'), 100);
      expect(find.text('Gross sales'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
