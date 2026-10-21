import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/menu/presentation/manage_menu_screen.dart';
import 'package:top_coffee_pos/features/menu/data/menu_repository.dart';
import 'package:top_coffee_pos/features/menu/presentation/menu_editor_screen.dart';
import 'package:top_coffee_pos/features/subscription/data/subscription_repository.dart';
import '../../presentation/ui_polish_test.dart' show savePreview;

class MenuAuth extends Mock implements AuthRepository {}

class MenuSubscription extends Mock implements SubscriptionRepository {}

const branch = BranchSummary(id: 1, name: 'Riverside', code: 'PP-01');
const user = AuthenticatedUser(
  id: 1,
  name: 'Manager',
  email: 'menu@example.invalid',
  roles: ['manager'],
  permissions: ['products.manage'],
  branches: [branch],
);
final catalog = <String, dynamic>{
  'products': [],
  'categories': [
    {'id': 1, 'name': 'Coffee', 'sort_order': 0, 'is_active': true},
  ],
  'ingredients': [],
  'discounts': [],
  'modifiers': [],
};

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [360.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('menu fits $width text $scale dark $dark', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final auth = MenuAuth();
          when(() => auth.hasStoredToken()).thenAnswer((_) async => true);
          when(() => auth.getCurrentUser()).thenAnswer((_) async => user);
          final key = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authRepositoryProvider.overrideWithValue(auth),
                currentBranchProvider.overrideWith(
                  (ref) =>
                      CurrentBranchNotifier(ref, listenToAuth: false)
                        ..selectBranch(branch),
                ),
              ],
              child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: key,
                  child: const ManageMenuScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await savePreview(tester, key, 'manage-menu-$width-$scale-$dark');
          for (final section in [
            'Items',
            'Combos',
            'Categories',
            'Discounts',
            'Modifiers',
          ]) {
            await tester.scrollUntilVisible(
              find.text(section),
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.text(section).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await savePreview(
            tester,
            key,
            'manage-menu-scrolled-$width-$scale-$dark',
          );
        });
      }
    }
  }

  for (final width in [360.0, 800.0]) {
    for (final dark in [false, true]) {
      testWidgets('section search is clearable at $width dark $dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final subscription = MenuSubscription();
        when(
          () => subscription.getSubscription(),
        ).thenAnswer((_) async => throw Exception('Read-only preview'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              subscriptionRepositoryProvider.overrideWithValue(subscription),
              menuDataProvider.overrideWith((ref) async => catalog),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: key,
                child: const MenuSectionScreen(section: 'Categories'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Coffee'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '  coffee  ');
        await tester.pumpAndSettle();
        expect(find.text('Coffee'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'tea');
        await tester.pumpAndSettle();
        expect(find.text('No matches for “tea”.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await savePreview(tester, key, 'menu-search-empty-$width-$dark');
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Coffee'), findsOneWidget);
        expect(find.text('1 entry shown'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await savePreview(tester, key, 'menu-section-$width-$dark');
      });
    }
  }

  for (final withRecipe in [false, true]) {
    testWidgets('saved modifier reopens for editing, recipe $withRecipe', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith(
              (ref) =>
                  CurrentBranchNotifier(ref, listenToAuth: false)
                    ..selectBranch(branch),
            ),
          ],
          child: MaterialApp(
            home: MenuEditorScreen(
              section: 'Modifiers',
              catalog: {
                ...catalog,
                'ingredients': [
                  {'id': 7, 'name': 'Oat milk'},
                ],
              },
              initial: {
                'id': 3,
                'name': 'Milk choice',
                'min_select': 0,
                'max_select': 1,
                'is_required': false,
                'is_active': true,
                'products': [],
                'modifiers': [
                  {
                    'id': 8,
                    'name': 'Oat',
                    'price_delta': '0.45',
                    'is_active': true,
                    'recipe_items': withRecipe
                        ? [
                            {
                              'branch_id': 1,
                              'ingredient_id': 7,
                              'quantity_used': '0.200',
                            },
                            {
                              'branch_id': 2,
                              'ingredient_id': 99,
                              'quantity_used': '0.500',
                            },
                          ]
                        : [],
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final name = find.widgetWithText(TextFormField, 'Option name');
      await tester.scrollUntilVisible(
        name,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextFormField>(name).initialValue, 'Oat');
      final price = find.widgetWithText(TextFormField, 'Extra price');
      expect(tester.widget<TextFormField>(price).initialValue, '0.45');
      await tester.enterText(name, 'Oat milk');
      if (withRecipe) {
        final ingredient = find.byType(DropdownButtonFormField<int>);
        await tester.scrollUntilVisible(
          ingredient,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Oat milk'), findsWidgets);
        final quantity = find.widgetWithText(
          TextFormField,
          'Quantity in ingredient stock units',
        );
        expect(tester.widget<TextFormField>(quantity).initialValue, '0.200');
        expect(ingredient, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor exposes real choices and rejects empty combo', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBranchProvider.overrideWith(
            (ref) =>
                CurrentBranchNotifier(ref, listenToAuth: false)
                  ..selectBranch(branch),
          ),
        ],
        child: MaterialApp(
          home: MenuEditorScreen(section: 'Combos', catalog: catalog),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Morning combo',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Category'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one combo slot.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
