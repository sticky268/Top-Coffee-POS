import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';
import 'package:top_coffee_pos/features/reports/application/sales_reports_controller.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import 'package:top_coffee_pos/features/reports/presentation/reports_home_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/sales_history_screen.dart';
import 'sales_report_fixture.dart';
import 'inventory_reports_test.dart' show inventoryFixture;
import '../../presentation/ui_polish_test.dart' show savePreview;

class MockHistoryRepository extends Mock implements SalesReportsRepository {}

SalesReport historyFixture({bool monthly = false, bool empty = false}) {
  final source = salesReportFixture();
  return SalesReport({
    'meta': {
      ...source.meta,
      'date_from': monthly ? '2026-01-01' : '2026-09-20',
      'date_to': '2026-10-19',
    },
    'summary': source.summary,
    'comparisons': source.comparisons,
    'payment_methods': source.paymentMethods,
    'hourly_sales': [],
    'top_products': [],
    'order_types': [],
    'cash_flow': source.cashFlow,
    'shifts': source.shifts,
    'timeline': monthly
        ? [
            for (var month = 1; month <= 12; month++)
              {
                'date_from': '2026-${month.toString().padLeft(2, '0')}-01',
                'date_to': '2026-${month.toString().padLeft(2, '0')}-28',
                'total': month > 10 || empty
                    ? '0.00'
                    : month == 10
                        ? '1405.54'
                        : '65.95',
                'orders': month > 10 || empty ? 0 : 4,
                'items': month > 10 || empty ? 0 : 32,
                'upcoming': month > 10,
              },
          ]
        : [
            for (var day = 17; day <= 19; day++)
              {
                'date_from': '2026-10-$day',
                'date_to': '2026-10-$day',
                'total': empty
                    ? '0.00'
                    : day == 18
                        ? '1405.54'
                        : '65.95',
                'orders': empty ? 0 : 4,
                'items': empty ? 0 : 32,
                'upcoming': false,
              },
          ],
  });
}

ProviderContainer scope(MockHistoryRepository repository) => ProviderContainer(
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

Future<void> showPage(
  WidgetTester tester,
  ProviderContainer container,
  Widget page, {
  double width = 360,
  double scale = 1,
  bool dark = false,
  GlobalKey? preview,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: preview,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

  for (final width in [360.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'reports menu and daily history fit $width/$scale/dark=$dark',
          (tester) async {
            final repository = MockHistoryRepository();
            when(
              () => repository.load(any(), 21),
            ).thenAnswer((_) async => historyFixture());
            final container = scope(repository);
            addTearDown(container.dispose);
            final key = GlobalKey();
            await showPage(
              tester,
              container,
              const ReportsHomeScreen(),
              width: width,
              scale: scale,
              dark: dark,
              preview: key,
            );
            expect(find.text('The coffee shop, in focus'), findsOneWidget);
            verifyNever(() => repository.load(any(), any()));
            expect(tester.takeException(), isNull);
            await savePreview(tester, key, 'reports-menu-$width-$scale-$dark');
            final history = find.text('Sale Reports');
            await tester.scrollUntilVisible(
              history,
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            final scroll = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            scroll.jumpTo(
              (scroll.pixels + tester.getCenter(history).dy - 350).clamp(
                scroll.minScrollExtent,
                scroll.maxScrollExtent,
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(history);
            await tester.pumpAndSettle();
            expect(find.text('Daily'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await savePreview(tester, key, 'sales-history-$width-$scale-$dark');
            {
              final amount = find.descendant(
                of: find.byKey(const ValueKey('history-2026-10-19')),
                matching: find.text(r'$65.95'),
              );
              expect(
                tester.getRect(amount).right,
                greaterThan(width - 80),
                reason:
                    'Amounts align at the trailing edge like the reference.',
              );
            }
            await tester.scrollUntilVisible(
              find.text('Top'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await savePreview(
              tester,
              key,
              'sales-history-rows-$width-$scale-$dark',
            );
            expect(find.text('4 Sales · 32 Items'), findsWidgets);
            expect(find.text('Top'), findsOneWidget);
            expect(find.text(r'$1,405.54'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'sales filters retain their values across daily and monthly tabs',
    (tester) async {
      final repository = MockHistoryRepository();
      when(() => repository.load(any(), 21)).thenAnswer((call) async {
        final query = call.positionalArguments.first as SalesReportQuery;
        return historyFixture(monthly: query.period == 'year');
      });
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(
        tester,
        container,
        const SalesHistoryScreen(),
        width: 800,
        scale: 2,
      );
      expect(find.text('Your sales from the last 30 days'), findsOneWidget);
      expect(find.text('Cashier'), findsNothing);
      await tester.tap(find.byTooltip('Sales filters'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<int>, 'Cashier'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manager').last);
      await tester.pumpAndSettle();
      expect(find.text('Filtered sales'), findsOneWidget);
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      final sent = verify(
        () => repository.load(captureAny(), 21),
      ).captured.cast<SalesReportQuery>();
      expect(sent.last.period, 'year');
      expect(sent.last.cashierId, 16);
      await tester.tap(find.byTooltip('Sales filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filtered sales'), findsNothing);
      final cleared = verify(
        () => repository.load(captureAny(), 21),
      ).captured.cast<SalesReportQuery>();
      expect(cleared.last.period, 'year');
      expect(cleared.last.cashierId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'menu analytical entry opens filters and reloads their selection',
    (tester) async {
      final repository = MockHistoryRepository();
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => salesReportFixture());
      when(
        () => repository.inventory(any(), 21),
      ).thenAnswer((_) async => inventoryFixture());
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(
        tester,
        container,
        const ReportWorkspaceScreen(kind: ReportWorkspace.inventory),
      );
      expect(find.text('Inventory report'), findsOneWidget);
      await tester.tap(find.text('Change date and report filters'));
      await tester.pumpAndSettle();
      expect(find.text('Sales summary'), findsOneWidget);
      await container
          .read(salesReportsControllerProvider.notifier)
          .select(const SalesReportQuery(categoryId: 1));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final sent = verify(
        () => repository.inventory(captureAny(), 21),
      ).captured.cast<SalesReportQuery>();
      expect(sent.last.categoryId, 1);
      expect(sent.last.comparisonFrom, '2026-10-18');
      expect(find.text('Inventory report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'monthly history shows all twelve months and opens its exact period',
    (tester) async {
      final repository = MockHistoryRepository();
      when(() => repository.load(any(), 21)).thenAnswer((call) async {
        final query = call.positionalArguments.first as SalesReportQuery;
        return historyFixture(monthly: query.period == 'year');
      });
      final container = scope(repository);
      addTearDown(container.dispose);
      final key = GlobalKey();
      await showPage(
        tester,
        container,
        const SalesHistoryScreen(),
        width: 800,
        preview: key,
      );
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
      expect(find.text('Upcoming'), findsNWidgets(2));
      expect(find.text('October 2026'), findsOneWidget);
      await savePreview(tester, key, 'sales-history-monthly-tablet');
      await tester.tap(find.text('October 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Sales summary'), findsOneWidget);
      final sent = verify(
        () => repository.load(captureAny(), 21),
      ).captured.cast<SalesReportQuery>();
      expect(
        sent.any((q) => q.period == 'month' && q.year == 2026 && q.month == 10),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily card opens exact dates and can be opened again after back',
    (tester) async {
      final repository = MockHistoryRepository();
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => historyFixture());
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(tester, container, const SalesHistoryScreen());
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byKey(const ValueKey('history-2026-10-19')));
        await tester.pumpAndSettle();
        expect(find.text('Sales summary'), findsOneWidget);
        final query =
            container.read(salesReportsControllerProvider.notifier).query;
        expect(query.period, 'custom');
        expect(query.dateFrom, '2026-10-19');
        expect(query.dateTo, '2026-10-19');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Sale Reports'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'upcoming month does not open a summary or issue another request',
    (tester) async {
      final repository = MockHistoryRepository();
      when(() => repository.load(any(), 21)).thenAnswer(
        (call) async => historyFixture(
          monthly:
              (call.positionalArguments.first as SalesReportQuery).period ==
                  'year',
        ),
      );
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(tester, container, const SalesHistoryScreen(), width: 800);
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      clearInteractions(repository);
      await tester.tap(find.text('December 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Sale Reports'), findsOneWidget);
      expect(find.text('Sales summary'), findsNothing);
      verifyNever(() => repository.load(any(), any()));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed pull-to-refresh shows retry and recovers without an uncaught error',
    (tester) async {
      final repository = MockHistoryRepository();
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => historyFixture());
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(tester, container, const SalesHistoryScreen());
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => throw Exception('offline'));
      await tester.drag(
        find.byKey(const ValueKey('sales-history-list')),
        const Offset(0, 450),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry history'), findsOneWidget);
      expect(tester.takeException(), isNull);
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => historyFixture());
      await tester.tap(find.text('Retry history'));
      await tester.pumpAndSettle();
      expect(find.text('19 Oct 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zero history has no top badge and retry recovers an offline request',
    (tester) async {
      final repository = MockHistoryRepository();
      when(() => repository.load(any(), 21)).thenThrow(Exception('offline'));
      final container = scope(repository);
      addTearDown(container.dispose);
      await showPage(tester, container, const SalesHistoryScreen());
      expect(find.text('Retry history'), findsOneWidget);
      when(
        () => repository.load(any(), 21),
      ).thenAnswer((_) async => historyFixture(empty: true));
      await tester.tap(find.text('Retry history'));
      await tester.pumpAndSettle();
      expect(find.text('Top'), findsNothing);
      expect(find.text('0 Sales · 0 Items'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('branch changes clear filters and do not expose stale history', (
    tester,
  ) async {
    final repository = MockHistoryRepository();
    final late = Completer<SalesReport>();
    when(() => repository.load(any(), 21)).thenAnswer((_) => late.future);
    when(
      () => repository.load(any(), 22),
    ).thenAnswer((_) async => historyFixture(empty: true));
    final container = scope(repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SalesHistoryScreen()),
      ),
    );
    await tester.pump();
    container
        .read(currentBranchProvider.notifier)
        .selectBranch(const BranchSummary(id: 22, name: 'Airport', code: 'AP'));
    await tester.pumpAndSettle();
    late.complete(historyFixture());
    await tester.pumpAndSettle();
    expect(find.text('Airport'), findsOneWidget);
    expect(find.text('Top'), findsNothing);
    expect(find.text('0 Sales · 0 Items'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
