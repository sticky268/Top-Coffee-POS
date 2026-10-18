import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/receipt/last_receipt_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/pos_screen.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/category_selector.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_card.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_search_field.dart';

import 'ui_polish_test.dart' show savePreview;

class PolishPosRepository extends Mock implements PosRepository {}

class PolishAuthRepository extends Mock implements AuthRepository {}

const _categories = [
  PosCategory(id: 1, name: 'Coffee', sortOrder: 1),
  PosCategory(id: 2, name: 'Tea & refreshments', sortOrder: 2),
  PosCategory(id: 3, name: 'Bakery', sortOrder: 3),
];
const _names = [
  'Iced Caramel Latte',
  'Espresso',
  'Matcha Latte',
  'Flat White',
  'Iced Lemon Tea',
  'Butter Croissant',
  'Cappuccino',
  'Cold Brew',
];
final _products = List.generate(
  _names.length,
  (index) => PosProduct(
    id: index + 1,
    name: _names[index],
    sku: 'MENU-$index',
    description: null,
    category: PosProductCategoryRef(
      id: index == 4 ? 2 : 1,
      name: index == 4 ? 'Tea & refreshments' : 'Coffee',
    ),
    price: index == 0 ? 3.5 : 2.5 + (index % 3) * 0.5,
    variants: const [],
  ),
);

void main() {
  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size,
    double scale,
    bool dark, {
    GlobalKey? preview,
    bool populate = true,
    bool shell = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PolishPosRepository();
    final auth = PolishAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => false);
    when(
      () => repository.getCategories(branchId: 21),
    ).thenAnswer((_) async => _categories);
    when(
      () => repository.getProducts(branchId: 21),
    ).thenAnswer((_) async => _products);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        posRepositoryProvider.overrideWithValue(repository),
        lastCompletedOrderProvider.overrideWith((ref) async => null),
        currentBranchProvider.overrideWith(
          (ref) => CurrentBranchNotifier(ref, listenToAuth: false)
            ..selectBranch(
              const BranchSummary(id: 21, name: 'Riverside', code: 'PP-01'),
            ),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (populate) {
      final cart = container.read(cartControllerProvider.notifier);
      cart.addItem(_products.first);
      cart.addItem(_products.first);
      cart.addItem(_products[1]);
    }
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
              key: preview,
              child: shell
                  ? const AppShell(selectedRoute: '/pos', child: PosScreen())
                  : const PosScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final size in [
    const Size(360, 800),
    const Size(600, 900),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('cashier workspace $size, text $scale, dark $dark', (
          tester,
        ) async {
          final preview = GlobalKey();
          await pump(tester, size, scale, dark, preview: preview);
          expect(tester.takeException(), isNull);
          expect(find.text('Takeaway'), findsOneWidget);
          expect(find.text('Review Order'), findsOneWidget);
          expect(find.text('2 in cart'), findsOneWidget);
          if (scale == 1 || (size.width == 360 && !dark)) {
            await savePreview(
              tester,
              preview,
              'workspace-${size.width.toInt()}-${dark ? 'dark' : 'light'}-text-${scale.toInt()}',
            );
          }
        });
      }
    }
  }

  testWidgets('phone menu scrolls filters away and keeps cart accessible', (
    tester,
  ) async {
    final container = await pump(
      tester,
      const Size(390, 844),
      1,
      false,
      populate: false,
      shell: true,
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.getSize(find.byType(AppBar)).height, lessThanOrEqualTo(56));
    expect(tester.getTopLeft(find.byType(ProductCard).first).dy, lessThan(220));
    expect(find.byType(ProductSearchField).hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(ProductSearchField).hitTestable(), findsNothing);
    expect(find.byType(CategorySelector).hitTestable(), findsNothing);
    await tester.tap(find.byType(ProductCard).hitTestable().first);
    await tester.pumpAndSettle();
    expect(container.read(cartControllerProvider).totalItemCount, 1);
    expect(find.byTooltip('View cart').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.byType(ProductSearchField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short large-text workspace keeps cart and review reachable', (
    tester,
  ) async {
    await pump(tester, const Size(360, 480), 2, false);
    expect(tester.takeException(), isNull);
    expect(find.text('Review Order').hitTestable(), findsOneWidget);
    expect(find.byTooltip('View cart').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('View cart'));
    await tester.pumpAndSettle();
    expect(find.text('Order Summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'product tap updates cart feedback once and search clear restores menu',
    (tester) async {
      final container = await pump(
        tester,
        const Size(360, 800),
        1,
        false,
        populate: false,
      );
      await tester.tap(find.byType(ProductCard).first);
      await tester.pumpAndSettle();
      expect(container.read(cartControllerProvider).totalItemCount, 1);
      expect(container.read(cartControllerProvider).total, 3.5);
      expect(find.text('1 in cart'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'does not exist');
      await tester.pumpAndSettle();
      expect(find.byType(ProductCard), findsNothing);
      await tester.tap(find.byTooltip('Clear product search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.byType(ProductCard), findsWidgets);
      expect(container.read(cartControllerProvider).totalItemCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large category labels fit and keep their original selection callback',
    (tester) async {
      int? selected = 99;
      await tester.binding.setSurfaceSize(const Size(360, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: CategorySelector(
                  categories: _categories,
                  selectedCategoryId: 1,
                  onSelected: (id) => selected = id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      expect(selected, isNull);
      expect(
        tester.getSize(find.widgetWithText(ChoiceChip, 'All')).height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  testWidgets('search clear retains keyboard focus for the next entry', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductSearchField(onChanged: queries.add)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Latte');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear product search'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(queries.last, '');
  });
}
