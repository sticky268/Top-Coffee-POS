import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/features/operations/presentation/operations_screen.dart';
import 'package:top_coffee_pos/core/widgets/page_content.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/auth/presentation/login_screen.dart';
import 'package:top_coffee_pos/features/orders/data/orders_repository.dart';
import 'package:top_coffee_pos/features/orders/domain/order_models.dart';
import 'package:top_coffee_pos/features/orders/presentation/order_detail_screen.dart';
import 'package:top_coffee_pos/features/orders/presentation/widgets/order_list_tile.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/products/presentation/widgets/product_list_tile.dart';
import 'package:top_coffee_pos/features/settings/presentation/settings_screen.dart';
import 'package:top_coffee_pos/features/reports/presentation/reports_screen.dart';
import 'package:top_coffee_pos/features/reports/domain/sales_report.dart';
import '../features/reports/sales_report_fixture.dart';
import 'package:top_coffee_pos/features/reports/data/sales_reports_repository.dart';

import 'ui_polish_test.dart' show savePreview;

class MockAuthRepository extends Mock implements AuthRepository {}

class MockOrdersRepository extends Mock implements OrdersRepository {}

class MockOperationsRepository extends Mock implements OperationsRepository {}

class MockReportsRepository extends Mock implements SalesReportsRepository {}

const branch = BranchSummary(
  id: 21,
  name: 'Riverside Coffee and Bakery',
  code: 'PP-01',
);
const orderBranch = OrderBranchRef(
  id: 21,
  name: 'Riverside Coffee and Bakery',
  code: 'PP-01',
);
const cashier = OrderCashierRef(
  id: 16,
  name: 'Cashier with a long display name',
);
const summary = OrderSummary(
  id: 124,
  orderNumber: 121,
  uuid: 'fixture',
  orderType: 'takeaway',
  status: 'completed',
  subtotal: 5,
  discountTotal: 0,
  total: 5,
  branch: orderBranch,
  cashier: cashier,
  payment: null,
  createdAt: null,
);
const detail = OrderDetail(
  id: 124,
  orderNumber: 121,
  uuid: 'fixture',
  orderType: 'takeaway',
  status: 'cancelled',
  subtotal: 5,
  discountTotal: 0,
  total: 5,
  branch: orderBranch,
  cashier: cashier,
  payment: null,
  createdAt: null,
  items: [
    OrderLineItem(
      id: 1,
      productId: 6,
      productName: 'Iced Caramel Coffee with Oat Milk',
      variantName: 'Large',
      quantity: 1,
      unitPrice: 5,
      lineTotal: 5,
    ),
  ],
);
const product = PosProduct(
  id: 6,
  name: 'Iced Caramel Coffee with Oat Milk',
  sku: null,
  description: null,
  category: null,
  price: 5,
  variants: [],
);

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

  Future<void> pump(
    WidgetTester tester,
    Widget screen,
    Size size,
    double scale,
    bool dark, {
    GlobalKey? preview,
    MockOrdersRepository? orders,
    MockOperationsRepository? operations,
    MockReportsRepository? reports,
  }) async {
    final auth = MockAuthRepository();
    when(
      () => auth.hasStoredToken(),
    ).thenAnswer((_) async => operations != null);
    when(() => auth.getCurrentUser()).thenAnswer(
      (_) async => const AuthenticatedUser(
        id: 16,
        name: 'Manager',
        email: 'manager@example.invalid',
        roles: ['manager'],
        permissions: [
          'orders.create',
          'inventory.view',
          'inventory.adjust',
          'reports.view',
        ],
        branches: [branch],
      ),
    );
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          if (reports != null)
            salesReportsRepositoryProvider.overrideWithValue(reports),
          if (operations != null)
            operationsRepositoryProvider.overrideWithValue(operations),
          pendingOrdersProvider.overrideWith((ref) => Stream.value([])),
          if (orders != null)
            ordersRepositoryProvider.overrideWithValue(orders),
          currentBranchProvider.overrideWith(
            (ref) => CurrentBranchNotifier(ref, listenToAuth: false)
              ..selectBranch(branch),
          ),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: RepaintBoundary(key: preview, child: screen),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(360, 800),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'records, login and settings fit $size text $scale dark $dark',
          (tester) async {
            var taps = 0;
            var disabled = 0;
            final preview = GlobalKey();
            await pump(
              tester,
              Scaffold(
                body: PageContent(
                  child: ListView(
                    children: [
                      OrderListTile(order: summary, onTap: () => taps++),
                      ProductListTile(
                        product: product,
                        onEdit: () => taps++,
                        canModify: false,
                        onDisable: () => disabled++,
                      ),
                      const DetailValue(
                        label: 'Branch',
                        value: 'Riverside Coffee and Bakery — Phnom Penh',
                      ),
                    ],
                  ),
                ),
              ),
              size,
              scale,
              dark,
              preview: preview,
            );
            expect(find.text('Order PP-01-000121'), findsOneWidget);
            expect(find.text('Order PP-01-000124'), findsNothing);
            await tester.tap(find.text('Order PP-01-000121'));
            await tester.pumpAndSettle();
            expect(taps, 1);
            await tester.ensureVisible(find.text(product.name));
            await tester.pumpAndSettle();
            await tester.tap(find.text(product.name));
            await tester.pumpAndSettle();
            expect(taps, 1);
            expect(disabled, 0);
            expect(tester.takeException(), isNull);
            if (size.width == 360 && scale == 2 && !dark) {
              await savePreview(
                tester,
                preview,
                'management-records-large-text',
              );
            }
            await pump(tester, const SettingsScreen(), size, scale, dark);
            await tester.scrollUntilVisible(find.text('Receipt Settings'), 250);
            await tester.pumpAndSettle();
            expect(find.text('Receipt Settings').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await pump(tester, const LoginScreen(), size, scale, dark);
            final signIn = find.text('Sign in');
            await tester.ensureVisible(signIn);
            await tester.pumpAndSettle();
            await tester.tap(signIn);
            await tester.pumpAndSettle();
            expect(find.text('Enter your email'), findsOneWidget);
            expect(find.text('Enter your password'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'reports keep range choices and long totals readable at 200 percent',
    (tester) async {
      final reports = MockReportsRepository();
      when(
        () => reports.load(any(), any()),
      ).thenAnswer((_) async => salesReportFixture());
      final preview = GlobalKey();
      await pump(
        tester,
        const ReportsScreen(),
        const Size(360, 800),
        2,
        false,
        reports: reports,
        preview: preview,
      );
      await tester.tap(find.text('Dates & filters'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, '7 Days'),
        150,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '7 Days'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sales breakdown'), 300);
      await tester.tap(find.text('Sales breakdown'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gross sales'), 150);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview, 'reports-large-text');
      await tester.scrollUntilVisible(
        find.text('Cash drawer reconciliation'),
        300,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      verify(() => reports.load(any(), any())).called(2);
    },
  );

  testWidgets('Daily Operations sections and retry fit phone large text', (
    tester,
  ) async {
    final operations = MockOperationsRepository();
    final pending = <Map<String, dynamic>>[
      {
        'path': '/stock/count',
        'uuid': '621f0e83-69ca-4ad4-bff6-845d216e8024',
        'rejected': false,
        'error': 'Confirmation could not be received',
      },
    ];
    when(() => operations.pending()).thenAnswer((_) async => pending);
    when(() => operations.get(any(), query: any(named: 'query'))).thenAnswer((
      call,
    ) async {
      return switch (call.positionalArguments.first) {
        '/ingredients' => [
            {
              'id': 11,
              'name': 'Coffee Bean with a long supplier description',
              'current_stock': 49.978,
              'unit': {'abbreviation': 'kg'},
            },
          ],
        '/products/availability' => [
            {
              'name': 'Iced Caramel Coffee with Oat Milk',
              'available_servings': 10,
              'ingredient_cost': 1.2,
            },
          ],
        '/reports/operations' => {
            'gross_sales': 25,
            'refunds': 5,
            'net_sales': 20,
          },
        _ => <Map<String, dynamic>>[],
      };
    });
    when(() => operations.retry(any())).thenAnswer((_) async {
      pending.clear();
      return null;
    });
    final preview = GlobalKey();
    await pump(
      tester,
      const OperationsScreen(),
      const Size(360, 800),
      2,
      false,
      operations: operations,
      preview: preview,
    );
    for (final section in ['Stock counts', 'Availability', 'Owner report']) {
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, section));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, section));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(find.text('Gross receipts'), 300);
    await tester.pumpAndSettle();
    await savePreview(tester, preview, 'daily-operations-large-text');
    await tester.scrollUntilVisible(find.text('Retry original action'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Retry original action').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Retry original action'));
    await tester.pumpAndSettle();
    verify(() => operations.retry(any())).called(1);
    verifyNever(() => operations.write(any(), any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'historical detail keeps receipt identity and scrolls through long content',
    (tester) async {
      final orders = MockOrdersRepository();
      when(() => orders.getOrder(124)).thenAnswer((_) async => detail);
      final preview = GlobalKey();
      await pump(
        tester,
        const OrderDetailScreen(orderId: 124),
        const Size(360, 800),
        2,
        false,
        orders: orders,
        preview: preview,
      );
      expect(find.text('Order PP-01-000121'), findsNWidgets(2));
      expect(find.text('Order PP-01-000124'), findsNothing);
      await tester.scrollUntilVisible(find.text('Items'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview, 'order-detail-large-text');
      await tester.scrollUntilVisible(find.text('Total'), 300);
      await tester.pumpAndSettle();
      expect(find.text('\$5.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      verify(() => orders.getOrder(124)).called(1);
      verifyNoMoreInteractions(orders);
    },
  );
}
