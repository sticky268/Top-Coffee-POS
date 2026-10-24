import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/dashboard/domain/dashboard_models.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_header.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/dashboard_navigation.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/quick_actions_grid.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/recent_orders_section.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/widgets/stat_cards_grid.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_grid.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

const branch = BranchSummary(
  id: 21,
  name: 'Riverside Coffee Main Branch',
  code: 'PP-01',
);
const user = AuthenticatedUser(
  id: 16,
  name: 'Panha',
  email: 'preview@example.invalid',
  roles: ['admin'],
  permissions: ['branches.view-all'],
  branches: [branch],
);
const stats = DashboardStats(
  todaysSales: 1248.50,
  todaysOrders: 86,
  averageOrderValue: 14.52,
  lowStockItemCount: 5,
);
const product = PosProduct(
  id: 1,
  name: 'Iced Caramel Latte with Oat Milk',
  sku: null,
  description: null,
  category: null,
  price: 3.50,
  variants: [],
);

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'dashboard cards fit ${size.width} x ${size.height}, text $scale, dark $dark',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final container = ProviderContainer(
              overrides: [
                currentBranchProvider.overrideWith((ref) {
                  final notifier = CurrentBranchNotifier(
                    ref,
                    listenToAuth: false,
                  )..selectBranch(branch);
                  return notifier;
                }),
              ],
            );
            addTearDown(container.dispose);
            var taps = 0;
            final key = GlobalKey();
            final columns = size.width < 600 ? (scale > 1.4 ? 1 : 2) : 4;
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: Scaffold(
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DashboardHeader(user: user, onLogout: () {}),
                              const SizedBox(height: 24),
                              StatCardsGrid(
                                stats: stats,
                                crossAxisCount: columns,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Quick Actions',
                                style: (dark ? AppTheme.dark : AppTheme.light)
                                    .textTheme
                                    .titleLarge,
                              ),
                              const SizedBox(height: 16),
                              QuickActionsGrid(
                                crossAxisCount: columns,
                                actions: [
                                  QuickAction(
                                    label: 'New Order',
                                    icon: Icons.add_shopping_cart,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Orders',
                                    icon: Icons.receipt_long_outlined,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Customers',
                                    icon: Icons.people_outline,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Manage Menu',
                                    icon: Icons.local_cafe_outlined,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Inventory',
                                    icon: Icons.inventory_2_outlined,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Reports',
                                    icon: Icons.bar_chart_outlined,
                                    onTap: () => taps++,
                                  ),
                                  QuickAction(
                                    label: 'Receipt Settings',
                                    icon: Icons.receipt_long,
                                    onTap: () => taps++,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              RecentOrdersSection(
                                orders: [
                                  RecentOrder(
                                    orderNumber: '#121',
                                    time: DateTime(2026, 10, 14, 10, 30),
                                    itemCount: 3,
                                    total: 1234567.89,
                                    status: OrderStatus.completed,
                                    customerOrTable:
                                        'Riverside table with a long customer reference',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Receipt Settings'));
            await tester.tap(find.text('Receipt Settings'));
            await tester.pumpAndSettle();
            expect(taps, 1);
            expect(tester.takeException(), isNull);
            // Export representative rendered widgets for visual review in CI.
            if (scale == 1 && (!dark || size.width == 360)) {
              await tester.drag(
                find.byType(SingleChildScrollView).first,
                const Offset(0, 3000),
              );
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final boundary = key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final folder = Directory('build/ui-polish')
                  ..createSync(recursive: true);
                File(
                  '${folder.path}/dashboard-${size.width.toInt()}-${dark ? 'dark' : 'light'}.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          },
        );
      }
    }
  }

  testWidgets('large text product cards remain usable and add exactly once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    final previewKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(
              key: previewKey,
              child: Scaffold(
                body: ProductGrid(
                  products: const [product],
                  crossAxisCount: 2,
                  onProductSelected: (_) => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(product.name));
    expect(taps, 1);
    expect(find.text('\$3.50'), findsOneWidget);
    await savePreview(tester, previewKey, 'pos-360-large-text');
  });

  for (final width in [259.0, 459.0, 939.0]) {
    testWidgets('product grid fits the actual tablet catalog pane $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ProductGrid(
                products: const [product],
                crossAxisCount: 4,
                onProductSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final grid = tester.widget<GridView>(find.byType(GridView));
      final columns =
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount;
      expect(
        columns,
        width < 300
            ? 1
            : width < 600
                ? 2
                : 4,
      );
      final price = tester.renderObject<RenderParagraph>(find.text('\$3.50'));
      expect(price.didExceedMaxLines, isFalse);
    });
  }

  testWidgets('Categories selects the Manage Menu navigation item',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = MockAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const MaterialApp(
          home: Scaffold(
            body: DashboardNavigation(selectedRoute: '/products/categories'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((tile) => tile.selected)
        .toList();
    expect(selected, hasLength(1));
    expect((selected.single.title! as Text).data, 'Manage Menu');
    expect(tester.takeException(), isNull);
  });
}

Future<void> savePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/ui-polish')..createSync(recursive: true);
    File(
      '${folder.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
