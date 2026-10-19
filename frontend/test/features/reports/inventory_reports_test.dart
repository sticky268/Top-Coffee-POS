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
import 'package:top_coffee_pos/features/reports/domain/inventory_report.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/inventory_report_screen.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockInventoryRepository extends Mock implements SalesReportsRepository {}

Map<String, dynamic> inventoryFixture() {
  final row = <String, dynamic>{
    for (final key in inventoryLabels.keys)
      key: inventoryCostKeys.contains(key) ? '1.999002' : '1.999',
    'comparisons': {
      for (final key in inventoryLabels.keys)
        key: {
          'previous': inventoryCostKeys.contains(key) ? '1.000001' : '1.000',
          'percent': '99.90',
          'status': 'comparable'
        }
    },
    'id': 9,
    'name': '=Coffee',
    'branch_name': 'Riverside',
    'branch_id': 21,
    'unit': 'g',
    'active': true,
    'low_stock': true,
    'ledger_review': false,
    'threshold': '2.000',
    'known_expected': '1.999',
    'known_waste_cost': '0.001000',
  };
  final summary = <String, dynamic>{
    for (final key in inventorySummaryLabels.keys)
      key: inventoryCostKeys.contains(key) ? '1.999002' : 1,
    'comparisons': {
      for (final key in inventorySummaryLabels.keys)
        key: {
          'previous': inventoryCostKeys.contains(key) ? '1.000001' : '0',
          'percent': '99.90',
          'status': 'comparable'
        }
    },
  };
  return {
    'meta': {
      'branches': [
        {'id': 21, 'name': 'Riverside', 'timezone': 'Asia/Phnom_Penh'}
      ],
      'date_from': '2026-10-19',
      'date_to': '2026-10-19',
      'previous_from': '2026-10-18',
      'previous_to': '2026-10-18',
      'cashier_name': 'Cashier',
      'category_name': 'Drinks',
      'basis':
          'Branch-wide ledger stock. Selected paid-sale usage; legacy recipes unavailable.',
      'generated_at': '2026-10-19T02:00:00Z'
    },
    'summary': summary,
    'ingredients': [row]
  };
}

Map<String, dynamic> inventorySources(int page) => {
      'ingredient': {
        'id': 9,
        'name': '=Coffee',
        'branch_name': 'Riverside',
        'unit': 'g'
      },
      'kind': 'sales',
      'page': page,
      'per_page': 50,
      'total': 51,
      'rows': [
        {
          'order_id': page,
          'order_number': page,
          'expected': '1.999',
          'deducted': '1.999',
          'returned': '0.000',
          'missing_recipe_lines': 0
        }
      ],
    };
const inventoryQuery = SalesReportQuery(
    period: 'custom',
    dateFrom: '2026-10-19',
    dateTo: '2026-10-19',
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
      'inventory exports retain numeric costs and quantities, literal names and unavailable history',
      () async {
    final data = inventoryFixture();
    (data['ingredients'] as List).first['expected'] = null;
    (data['ingredients'] as List).first['variance'] = null;
    final rows = inventoryReportRows(data);
    final sheet = utf8.decode(ZipDecoder()
        .decodeBytes(ReportExporter.xlsx(rows))
        .findFile('xl/worksheets/sheet1.xml')!
        .content);
    expect(sheet, contains('t="n"><v>1.999002</v>'));
    expect(sheet, contains('t="n"><v>1.999</v>'));
    expect(sheet, contains('Unavailable'));
    expect(sheet, contains('=Coffee'));
    expect(ReportExporter.csv(rows), contains("'=Coffee"));
    expect(ReportInventoryCost.parse('99999999999999999999.123456').toString(),
        '99999999999999999999.123456');
    final dir = Directory('build/report-exports')..createSync(recursive: true);
    for (final format in [ReportExportFormat.xlsx, ReportExportFormat.pdf]) {
      final file = await ReportExporter.buildRows(
          rows, 'inventory-exact', format,
          title: 'Inventory report', columnFlex: [5, 3, 3, 3]);
      File('${dir.path}/${file.name}').writeAsBytesSync(file.bytes);
    }
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'inventory phone scale $scale opens exact paid-sale source filters',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockInventoryRepository();
      when(() => repository.inventory(any(), 21))
          .thenAnswer((_) async => inventoryFixture());
      when(() => repository.inventory(any(), 21,
          detail: true,
          ingredientId: 9,
          kind: 'sales',
          page: 1)).thenAnswer((_) async => inventorySources(1));
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
                      child: const InventoryReportScreen(
                          query: inventoryQuery, branchId: 21))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await savePreview(tester, key, 'inventory-overview-$scale.png');
      final ingredient = find.byKey(const ValueKey('inventory-ingredient-9'));
      await tester.scrollUntilVisible(ingredient, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('=Coffee / Riverside'));
      await tester.pumpAndSettle();
      final actual =
          find.widgetWithText(ListTile, 'Actual gross sale deductions');
      await tester.scrollUntilVisible(actual, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final vertical =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      vertical.jumpTo((vertical.pixels + tester.getCenter(actual).dy - 400)
          .clamp(vertical.minScrollExtent, vertical.maxScrollExtent));
      await tester.pumpAndSettle();
      expect(actual.hitTestable(), findsOneWidget);
      await savePreview(tester, key, 'inventory-ingredient-$scale.png');
      await tester.tap(actual);
      await tester.pumpAndSettle();
      expect(find.text('Order 1'), findsOneWidget);
      final query = verify(() => repository.inventory(captureAny(), 21,
          detail: true,
          ingredientId: 9,
          kind: 'sales',
          page: 1)).captured.single as SalesReportQuery;
      expect(query.cashierId, 5);
      expect(query.categoryId, 6);
      expect(query.dateFrom, '2026-10-19');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'inventory source pagination hides stale rows and retries requested page',
      (tester) async {
    final repository = MockInventoryRepository();
    final next = Completer<Map<String, dynamic>>();
    when(() => repository.inventory(any(), 21,
        detail: true,
        ingredientId: 9,
        kind: 'sales',
        page: 1)).thenAnswer((_) async => inventorySources(1));
    when(() => repository.inventory(any(), 21,
        detail: true,
        ingredientId: 9,
        kind: 'sales',
        page: 2)).thenAnswer((_) => next.future);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          salesReportsRepositoryProvider.overrideWithValue(repository)
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const InventorySourcesScreen(
                query: inventoryQuery,
                branchId: 21,
                ingredientId: 9,
                kind: 'sales'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Order 1'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    next.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    when(() => repository.inventory(any(), 21,
        detail: true,
        ingredientId: 9,
        kind: 'sales',
        page: 2)).thenAnswer((_) async => inventorySources(2));
    await tester.tap(find.text('Retry inventory sources'));
    await tester.pumpAndSettle();
    expect(find.text('Order 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
