import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/trends_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/shift_reports_screen.dart';
import 'sales_report_fixture.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class TrendRepository extends Mock implements SalesReportsRepository {}

SalesReport fixture(SalesReportQuery query, {bool shifts = false}) {
  final base = salesReportFixture();
  final year = query.year ?? 2026;
  final timeline = query.period == 'year'
      ? [
          for (var m = 1; m <= 12; m++)
            {
              'date_from': '$year-${m.toString().padLeft(2, '0')}-01',
              'date_to': '$year-${m.toString().padLeft(2, '0')}-28',
              'total': m == 3 ? '0.00' : '120.00',
              'upcoming': year == 2026 && m > 3
            }
        ]
      : [
          for (var day = 12; day <= 18; day++)
            {
              'date_from': '2026-03-$day',
              'date_to': '2026-03-$day',
              'total': day == 13 ? '0.00' : '120.00'
            }
        ];
  return SalesReport({
    'meta': {
      ...base.meta,
      'today': '2026-03-18',
      'date_from': '2026-03-18',
      'date_to': '2026-03-18'
    },
    'summary': base.summary,
    'comparisons': base.comparisons,
    'timeline': timeline,
    'payment_methods': base.paymentMethods,
    'hourly_sales': [],
    'top_products': [],
    'order_types': [],
    'cash_flow': base.cashFlow,
    'shifts': shifts
        ? {
            'total': 1,
            'rows': [
              {
                'id': 8,
                'branch_id': 21,
                'cashier_name': 'Sok',
                'status': 'closed',
                'expected': '50.00',
                'opening': '10.00',
                'cash_sales': '40.00',
                'counted': '49.00',
                'difference': '-1.00'
              }
            ]
          }
        : base.shifts,
  });
}

void main() {
  setUpAll(() async {
    registerFallbackValue(const SalesReportQuery());
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  test('six months cross the year boundary and preserve the selected scope',
      () async {
    final repository = TrendRepository();
    when(() => repository.load(any(), 21)).thenAnswer(
        (c) async => fixture(c.positionalArguments[0] as SalesReportQuery));
    final trends = await SalesTrends.load(
        repository, const SalesReportQuery(cashierId: 5, categoryId: 6), 21);
    expect(trends.months.map((r) => r['date_from']), [
      '2025-10-01',
      '2025-11-01',
      '2025-12-01',
      '2026-01-01',
      '2026-02-01',
      '2026-03-01'
    ]);
    final queries = verify(() => repository.load(captureAny(), 21))
        .captured
        .cast<SalesReportQuery>();
    expect(queries.length, 5);
    expect(queries.every((q) => q.cashierId == 5 && q.categoryId == 6), isTrue);
  });

  for (final layout in [
    (const Size(390, 844), 1.0, false),
    (const Size(1024, 900), 1.0, true),
    (const Size(360, 800), 2.0, false)
  ]) {
    testWidgets('trends charts and source links fit $layout', (tester) async {
      await tester.binding.setSurfaceSize(layout.$1);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TrendRepository();
      when(() => repository.load(any(), 21)).thenAnswer(
          (c) async => fixture(c.positionalArguments[0] as SalesReportQuery));
      when(() => repository.details(any(), 21,
              kind: 'orders', metric: 'total_sales', page: 1))
          .thenAnswer(
              (_) async => {'rows': <Map<String, dynamic>>[], 'total': 0});
      final preview = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            salesReportsRepositoryProvider.overrideWithValue(repository)
          ],
          child: MaterialApp(
              theme: layout.$3 ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                  data: MediaQueryData(
                      size: layout.$1,
                      textScaler: TextScaler.linear(layout.$2)),
                  child: RepaintBoundary(
                      key: preview,
                      child: const TrendsScreen(
                          query: SalesReportQuery(cashierId: 5, categoryId: 6),
                          branchId: 21))))));
      await tester.pumpAndSettle();
      expect(find.text('Your sales rhythm'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview,
          'trends-${layout.$1.width}-${layout.$2}-${layout.$3}');
      final bar = find.byKey(const ValueKey('trend-2026-03-12'));
      await tester.scrollUntilVisible(bar.hitTestable(), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(bar);
      await tester.pumpAndSettle();
      await savePreview(tester, preview,
          'trends-chart-${layout.$1.width}-${layout.$2}-${layout.$3}');
      await tester.tap(bar.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Report source records'), findsOneWidget);
      final query = verify(() => repository.details(captureAny(), 21,
          kind: 'orders',
          metric: 'total_sales',
          page: 1)).captured.single as SalesReportQuery;
      expect(query.dateFrom, '2026-03-12');
      expect(query.dateTo, '2026-03-12');
      expect(query.cashierId, 5);
      expect(query.categoryId, 6);
      expect(tester.takeException(), isNull);
    });
  }

  for (final populated in [false, true]) {
    testWidgets(
        'shift report shows ${populated ? 'cash details' : 'an honest empty state'}',
        (tester) async {
      final repository = TrendRepository();
      when(() => repository.load(any(), 21)).thenAnswer((c) async => fixture(
          c.positionalArguments[0] as SalesReportQuery,
          shifts: populated));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            salesReportsRepositoryProvider.overrideWithValue(repository),
            currentBranchProvider.overrideWith((ref) => CurrentBranchNotifier(
                ref,
                listenToAuth: false)
              ..selectBranch(
                  const BranchSummary(id: 21, name: 'Riverside', code: 'PP'))),
          ],
          child: MaterialApp(
              theme: AppTheme.light, home: const ShiftReportsScreen())));
      await tester.pumpAndSettle();
      if (populated) {
        final shift = find.text('Sok · Shift 8');
        await tester.scrollUntilVisible(shift.hitTestable(), 100);
        await tester.ensureVisible(shift);
        await tester.pumpAndSettle();
        await tester.tap(shift.hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Counted cash'), findsOneWidget);
        expect(find.text('-\$1.00'), findsOneWidget);
      } else {
        expect(find.text('No shifts in this period'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed trends load can retry', (tester) async {
    final repository = TrendRepository();
    when(() => repository.load(any(), 21))
        .thenAnswer((_) async => throw Exception('offline'));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          salesReportsRepositoryProvider.overrideWithValue(repository)
        ],
        child: const MaterialApp(
            home: TrendsScreen(query: SalesReportQuery(), branchId: 21))));
    await tester.pumpAndSettle();
    expect(find.text('Retry trends'), findsOneWidget);
    when(() => repository.load(any(), 21)).thenAnswer(
        (c) async => fixture(c.positionalArguments[0] as SalesReportQuery));
    await tester.tap(find.text('Retry trends'));
    await tester.pumpAndSettle();
    expect(find.text('Your sales rhythm'), findsOneWidget);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Your sales rhythm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('source-record retry recovers without a state-update exception',
      (tester) async {
    final repository = TrendRepository();
    when(() => repository.load(any(), 21)).thenAnswer(
        (c) async => fixture(c.positionalArguments[0] as SalesReportQuery));
    when(() => repository.details(any(), 21,
        kind: 'orders',
        metric: 'total_sales',
        page: 1)).thenAnswer((_) async => throw Exception('offline'));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          salesReportsRepositoryProvider.overrideWithValue(repository)
        ],
        child: const MaterialApp(
            home: TrendsScreen(query: SalesReportQuery(), branchId: 21))));
    await tester.pumpAndSettle();
    final today = find.widgetWithText(ListTile, 'Today');
    await tester.ensureVisible(today);
    await tester.pumpAndSettle();
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(find.text('Could not load source records.'), findsOneWidget);
    when(() => repository.details(any(), 21,
            kind: 'orders', metric: 'total_sales', page: 1))
        .thenAnswer(
            (_) async => {'rows': <Map<String, dynamic>>[], 'total': 0});
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load source records.'), findsNothing);
    expect(find.text('Report source records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
