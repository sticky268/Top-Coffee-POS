import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/activity_report_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/branch_comparison_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/inventory_report_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/profit_report_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/report_overview_widgets.dart';
import 'activity_reports_test.dart' show activityFixture;
import 'branch_comparison_test.dart' show branchesFixture;
import 'inventory_reports_test.dart' show inventoryFixture;
import 'profit_reports_test.dart' show fixture;
import '../../presentation/ui_polish_test.dart' show savePreview;

class OverviewRepository extends Mock implements SalesReportsRepository {}

void main() {
  setUpAll(() async {
    registerFallbackValue(const SalesReportQuery());
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  test('overview groups exact large monetary text without rounding', () {
    expect(reportDisplayValue(r'$90071992547409.123456'),
        r'$90,071,992,547,409.123456');
    expect(reportDisplayValue(r'-$1234.00'), r'-$1,234.00');
    expect(reportDisplayValue('Unavailable'), 'Unavailable');
  });

  for (final report in ['profit', 'branches', 'activity', 'inventory']) {
    for (final layout in [
      (const Size(390, 844), 1.0, false),
      (const Size(390, 844), 1.0, true),
      (const Size(1024, 900), 1.0, true),
      (const Size(360, 800), 2.0, false),
    ]) {
      testWidgets(
          '$report overview ${layout.$1} scale ${layout.$2} dark ${layout.$3}',
          (tester) async {
        await tester.binding.setSurfaceSize(layout.$1);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = OverviewRepository();
        when(() => repository.profit(any(), 21))
            .thenAnswer((_) async => fixture());
        when(() => repository.branchComparison(any(), null))
            .thenAnswer((_) async => branchesFixture());
        when(() => repository.activity(any(), 21))
            .thenAnswer((_) async => activityFixture());
        when(() => repository.inventory(any(), 21))
            .thenAnswer((_) async => inventoryFixture());
        var changes = 0;
        void change() => changes++;
        const query = SalesReportQuery(
            period: 'custom', dateFrom: '2026-10-19', dateTo: '2026-10-19');
        final Widget screen = switch (report) {
          'profit' => ProfitReportScreen(
              query: query, branchId: 21, onChangeFilters: change),
          'branches' =>
            BranchComparisonScreen(query: query, onChangeFilters: change),
          'activity' => ActivityReportScreen(
              query: query, branchId: 21, onChangeFilters: change),
          _ => InventoryReportScreen(
              query: query, branchId: 21, onChangeFilters: change),
        };
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
                  child: RepaintBoundary(key: preview, child: screen))),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(ReportOverview), findsOneWidget);
        expect(find.byType(ReportMetricTile), findsNWidgets(4));
        expect(find.textContaining('Previous period:'), findsNothing);
        if (report == 'activity') {
          expect(find.byKey(const ValueKey('activity-cell-1-0')), findsNothing);
          expect(find.text('Audited voids'), findsNothing);
        }
        if (report == 'inventory') {
          expect(find.text('Actual gross sale deductions'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await savePreview(tester, preview,
            'overview-$report-${layout.$1.width.toInt()}-${layout.$2}-${layout.$3}');
        final filter = find.widgetWithIcon(TextButton, Icons.tune);
        await tester.ensureVisible(filter);
        await tester.tap(filter);
        await tester.pumpAndSettle();
        expect(changes, 1);
        final scope = find.text('Report scope & comparison');
        await tester.ensureVisible(scope);
        await tester.pumpAndSettle();
        await tester.tap(scope);
        await tester.pumpAndSettle();
        expect(find.textContaining('Previous period: 18 Oct 2026'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('profit keeps incomplete costs visible above collapsed details',
      (tester) async {
    final repository = OverviewRepository();
    when(() => repository.profit(any(), 21))
        .thenAnswer((_) async => fixture(incomplete: true));
    await tester.pumpWidget(ProviderScope(
      overrides: [salesReportsRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const ProfitReportScreen(
              query: SalesReportQuery(), branchId: 21)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Total COGS, profit and margin are incomplete.'),
        findsOneWidget);
    expect(find.text('Incomplete'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory keeps unknown valuation and ledger review visible',
      (tester) async {
    final repository = OverviewRepository();
    final data = inventoryFixture();
    data['summary']['value'] = null;
    data['summary']['unknown_value_items'] = 1;
    data['summary']['ledger_review_items'] = 1;
    when(() => repository.inventory(any(), 21)).thenAnswer((_) async => data);
    await tester.pumpWidget(ProviderScope(
      overrides: [salesReportsRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const InventoryReportScreen(
              query: SalesReportQuery(), branchId: 21)),
    ));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            '1 ingredient(s) have unknown valuation · 1 need ledger review.'),
        findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('product rows expand comparisons and keep exact source filters',
      (tester) async {
    final repository = OverviewRepository();
    when(() => repository.profit(any(), 21)).thenAnswer((_) async => fixture());
    when(() => repository.profitDetails(any(), 21, productId: 1, page: 1))
        .thenAnswer((_) async =>
            {'rows': <Map<String, dynamic>>[], 'page': 1, 'total': 0});
    const query = SalesReportQuery(
        period: 'custom',
        dateFrom: '2026-10-19',
        dateTo: '2026-10-19',
        cashierId: 5,
        categoryId: 6);
    await tester.pumpWidget(ProviderScope(
      overrides: [salesReportsRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const ProfitReportScreen(query: query, branchId: 21)),
    ));
    await tester.pumpAndSettle();
    final heading = find.text('Best sellers · units');
    await tester.scrollUntilVisible(heading.hitTestable(), 150);
    await tester.ensureVisible(heading);
    await tester.pumpAndSettle();
    await tester.tap(heading.hitTestable());
    await tester.pumpAndSettle();
    final product = find.text('Latte សួស្តី');
    await tester.scrollUntilVisible(product.hitTestable(), 100);
    await tester.ensureVisible(product);
    await tester.pumpAndSettle();
    await tester.tap(product.hitTestable());
    await tester.pumpAndSettle();
    final group =
        find.ancestor(of: heading, matching: find.byType(ReportSection));
    final revenue = find.descendant(
        of: group,
        matching: find.widgetWithText(ListTile, 'Revenue excluding tax'));
    await tester.scrollUntilVisible(revenue.hitTestable(), 100);
    await tester.ensureVisible(revenue);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: group, matching: find.textContaining('100.00% vs previous')),
        findsWidgets);
    await tester.tap(revenue.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Profit source items'), findsOneWidget);
    final sent = verify(() =>
            repository.profitDetails(captureAny(), 21, productId: 1, page: 1))
        .captured
        .single as SalesReportQuery;
    expect(sent.parameters(21), query.parameters(21));
    expect(tester.takeException(), isNull);
  });
}
