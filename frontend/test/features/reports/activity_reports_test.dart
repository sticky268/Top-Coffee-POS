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
import 'package:top_coffee_pos/features/reports/domain/activity_report.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/activity_report_screen.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockActivityRepository extends Mock implements SalesReportsRepository {}

Map<String, dynamic> activityRow({bool empty = false}) => {
      for (final key in activityLabels.keys)
        key: activityMoney.contains(key)
            ? (empty
                ? '0.00'
                : key == 'net_sales'
                    ? '24.98'
                    : key == 'sales'
                        ? '24.99'
                        : '0.01')
            : (empty ? 0 : 1),
      'comparisons': {
        for (final key in activityLabels.keys)
          key: {
            'previous': activityMoney.contains(key) ? '0.00' : 0,
            'delta': activityMoney.contains(key) ? '0.00' : 0,
            'percent': null,
            'status': empty ? 'unchanged' : 'new',
          },
      },
      for (final key in activityRates.keys) ...{
        '${key}_rate': empty ? null : '100.00',
        '${key}_previous_rate': null,
        '${key}_change_points': null,
      },
    };
Map<String, dynamic> activityFixture() => {
      'meta': {
        'date_from': '2026-10-19',
        'date_to': '2026-10-19',
        'previous_from': '2026-10-18',
        'previous_to': '2026-10-18',
        'branches': [
          {'id': 21, 'name': 'Riverside', 'timezone': 'Asia/Phnom_Penh'},
        ],
        'basis':
            'Paid sales in branch-local time. Refunds follow original sale cashier. Audited voids only.',
        'flag_basis':
            'Minimum 20 own and peer observations; review prompts, not fraud findings.',
        'generated_at': '2026-10-19T02:00:00Z',
        'heatmap_max_net_cents': 2498,
        'heatmap_max_orders': 1,
      },
      'summary': activityRow(),
      'cashiers': [
        activityRow()
          ..addAll({
            'id': 5,
            'name': '=Cashier សួស្តី',
            'flags': ['discounted_orders'],
          }),
      ],
      'cells': [
        for (var d = 1; d <= 7; d++)
          for (var h = 0; h < 24; h++)
            activityRow(empty: d != 1 || h != 0)
              ..addAll({'weekday': d, 'hour': h}),
      ],
    };
Map<String, dynamic> sourcePage(int page) => {
      'rows': [
        activityRow()
          ..addAll({
            'order_id': page,
            'order_number': page,
            'branch_name': 'Riverside',
            'occurred_at_local': '2026-10-19 00:00:00 +07:00',
            'actors': ['Refund operator'],
          }),
      ],
      'page': page,
      'total': 51,
      'per_page': 50,
    };

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
  test(
    'activity exports retain exact numeric money, labels, all bins and literal cashier names',
    () async {
      final data = activityFixture();
      final rows = activityReportRows(data);
      final sheet = utf8.decode(
        ZipDecoder()
            .decodeBytes(ReportExporter.xlsx(rows))
            .findFile('xl/worksheets/sheet1.xml')!
            .content,
      );
      expect(sheet, contains('t="n"><v>24.98</v>'));
      expect(sheet, contains('=Cashier សួស្តី'));
      expect(ReportExporter.csv(rows), contains("'=Cashier"));
      expect(
        rows
            .where((r) => r.firstOrNull.toString().contains('/ Paid orders'))
            .length,
        168,
      );
      final compact = activityReportRows(data, compact: true);
      expect(
        compact
            .where((r) => r.firstOrNull.toString().contains('/ Paid orders'))
            .length,
        1,
      );
      expect(compact.any((r) => r.contains('Change (points)')), isTrue);
      expect(
        activityChange(activityRow(empty: true), 'orders'),
        'No comparable baseline',
      );
      final dir = Directory('build/report-exports')
        ..createSync(recursive: true);
      for (final format in [ReportExportFormat.xlsx, ReportExportFormat.pdf]) {
        final file = await ReportExporter.buildRows(
          format == ReportExportFormat.pdf ? compact : rows,
          'activity-exact',
          format,
          title: 'Time and cashier report',
          columnFlex: [5, 3, 3, 3],
        );
        File('${dir.path}/${file.name}').writeAsBytesSync(file.bytes);
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'time and cashier report fits phone at scale $scale and pins source filters',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = MockActivityRepository();
        when(
          () => repository.activity(any(), 21),
        ).thenAnswer((_) async => activityFixture());
        when(
          () => repository.activity(
            any(),
            21,
            detail: true,
            page: 1,
            weekday: 1,
            hour: 0,
          ),
        ).thenAnswer((_) async => sourcePage(1));
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              salesReportsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: key,
                  child: const ActivityReportScreen(
                    query: SalesReportQuery(
                      period: 'custom',
                      dateFrom: '2026-10-19',
                      dateTo: '2026-10-19',
                      cashierId: 5,
                      categoryId: 6,
                    ),
                    branchId: 21,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await savePreview(tester, key, 'activity-overview-$scale.png');
        final cell = find.byKey(const ValueKey('activity-cell-1-0'));
        await tester.scrollUntilVisible(
          cell,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Place the nested cell using the vertical scroll position; a drag
        // can fling past it before the next frame on different toolchains.
        await tester.pumpAndSettle();
        final vertical = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        for (var attempt = 0;
            attempt < 5 && (tester.getCenter(cell).dy - 400).abs() > 50;
            attempt++) {
          vertical.jumpTo((vertical.pixels + tester.getCenter(cell).dy - 400)
              .clamp(vertical.minScrollExtent, vertical.maxScrollExtent));
          await tester.pumpAndSettle();
        }
        expect(tester.getCenter(cell).dy, inInclusiveRange(56, 650));
        expect(cell.hitTestable(), findsOneWidget);
        await savePreview(tester, key, 'activity-heatmap-$scale.png');
        await tester.tap(cell);
        await tester.pumpAndSettle();
        expect(find.text('Order 1'), findsOneWidget);
        final captured = verify(
          () => repository.activity(
            captureAny(),
            21,
            detail: true,
            page: 1,
            weekday: 1,
            hour: 0,
          ),
        ).captured.single as SalesReportQuery;
        expect(captured.cashierId, 5);
        expect(captured.categoryId, 6);
        expect(captured.dateFrom, '2026-10-19');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'source paging hides retained data, exposes errors and retries the requested page',
    (tester) async {
      final repository = MockActivityRepository();
      final next = Completer<Map<String, dynamic>>();
      when(
        () => repository.activity(any(), 21),
      ).thenAnswer((_) async => activityFixture());
      when(
        () => repository.activity(any(), 21, detail: true, page: 1),
      ).thenAnswer((_) async => sourcePage(1));
      when(
        () => repository.activity(any(), 21, detail: true, page: 2),
      ).thenAnswer((_) => next.future);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            salesReportsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ActivityReportScreen(
              query: SalesReportQuery(
                period: 'custom',
                dateFrom: '2026-10-19',
                dateTo: '2026-10-19',
              ),
              branchId: 21,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sales =
          find.widgetWithText(ListTile, 'Paid sales including tax').first;
      await tester.ensureVisible(sales);
      await tester.tap(sales);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Order 1'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      next.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Retry source orders'), findsOneWidget);
      when(
        () => repository.activity(any(), 21, detail: true, page: 2),
      ).thenAnswer((_) async => sourcePage(2));
      await tester.tap(find.text('Retry source orders'));
      await tester.pumpAndSettle();
      expect(find.text('Order 2'), findsOneWidget);
      expect(find.textContaining('Page 2 /'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
