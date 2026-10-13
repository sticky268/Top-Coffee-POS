import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_card.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:top_coffee_pos/app.dart';
import 'package:top_coffee_pos/core/config/env.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/offline/order_sync.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_controller.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_state.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart' show cachedCatalogProvider;
import 'package:top_coffee_pos/features/operations/data/operations_repository.dart';
import 'package:top_coffee_pos/features/dashboard/presentation/dashboard_screen.dart';
import 'package:top_coffee_pos/features/operations/presentation/operations_screen.dart';

Future<void> waitForHome(WidgetTester tester) async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final previous = binding.shouldPropagateDevicePointerEvents;
  try {
    if (const bool.fromEnvironment('WAIT_FOR_LOGIN')) {
      binding.shouldPropagateDevicePointerEvents = true;
    }
    await _waitForHome(tester);
  } finally {
    binding.shouldPropagateDevicePointerEvents = previous;
  }
}

Future<void> _waitForHome(WidgetTester tester) async {
  const interactiveLogin = bool.fromEnvironment('WAIT_FOR_LOGIN');
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  var loginPrompted = false;
  for (
    var i = 0;
    interactiveLogin ? DateTime.now().isBefore(deadline) : i < 200;
    i++
  ) {
    if (interactiveLogin) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    }
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(DashboardScreen).evaluate().isNotEmpty) return;
    if (find.widgetWithText(TextFormField, 'Email').evaluate().isNotEmpty) {
      if (const bool.fromEnvironment('SMOKE_CI_LOGIN')) {
        expect(Env.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'cashier@ci.invalid',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'ci-disposable-password',
        );
        await tester.tap(find.text('Sign in').last);
        continue;
      }
      if (interactiveLogin) {
        if (!loginPrompted) {
          debugPrint(
            'ACTION: Sign in on the emulator now. The test will continue automatically (5 minute limit).',
          );
          loginPrompted = true;
        }
        continue;
      }
      fail(
        'No saved signed-in session. Sign in normally on this emulator, then rerun this test.',
      );
    }
  }
  fail(
    'The signed-in home screen did not load. Check the rehearsal API server.',
  );
}

Future<void> waitForOperations(WidgetTester tester) async {
  final refresh = find.descendant(
    of: find.byType(OperationsScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Refresh',
    ),
  );
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (refresh.evaluate().isNotEmpty &&
        tester.widget<IconButton>(refresh).onPressed != null) {
      expect(
        find.text('Could not load operations'),
        findsNothing,
        reason: 'The selected operations section returned a loading error.',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'The operations screen raised a rendering or runtime error.',
      );
      return;
    }
  }
  fail(
    'Daily Operations did not finish loading. Check the rehearsal API server.',
  );
}

Future<void> waitForControl(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'The shift action did not finish.');
}

double get rehearsalSalePrice =>
    double.parse(const String.fromEnvironment('SALE_PRICE', defaultValue: '3.50'));

Future<void> rehearseShift(
  WidgetTester tester, {
  bool includeSale = false,
}) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  if (includeSale) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OperationsScreen)),
    );
    expect(container.read(currentBranchProvider)?.id, 21);
  }
  const resumeId = int.fromEnvironment('RESUME_SHIFT_ID');
  if (resumeId > 0) {
    expect(includeSale, isTrue);
    final container = ProviderScope.containerOf(tester.element(find.byType(OperationsScreen)));
    final rows = await tester.runAsync(() =>
        container.read(operationsRepositoryProvider).get('/shifts'));
    final targets = (rows as List).cast<Map>().where((row) => row['id'] == resumeId).toList();
    expect(targets, hasLength(1), reason: 'The explicit rehearsal shift must exist.');
    final shift = targets.single;
    expect(shift['branch_id'], 21);
    expect(shift['user_id'], 16);
    expect(shift['status'], 'open');
    expect(num.parse('${shift['opening_cash']}'), 20);
    expect(shift['payment_totals'], isEmpty,
        reason: 'Refusing to repeat a sale on a shift with payments.');
    expect(shift['movements'], isEmpty);
    for (final key in ['cash_sales', 'cash_refunds', 'cash_in', 'cash_out']) {
      expect(num.parse('${shift[key]}'), 0);
    }
    expect(find.text('Shift #$resumeId · open'), findsOneWidget);
  } else {
    expect(
      find.widgetWithText(FilledButton, 'Close shift'),
      findsNothing,
      reason: 'Refusing to interfere with an existing open shift.',
    );
    final open = find.widgetWithText(FilledButton, 'Open shift');
    expect(
      open,
      findsOneWidget,
      reason: 'This account needs permission to open a shift.',
    );
    await tester.ensureVisible(open);
    await tester.tap(open);
    final openingCash = find.widgetWithText(TextFormField, 'Opening cash');
    await waitForControl(tester, openingCash);
    await tester.enterText(openingCash, '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  }
  final close = find.widgetWithText(FilledButton, 'Close shift');
  await waitForControl(tester, close);
  final card = find.ancestor(of: close, matching: find.byType(Card)).first;
  final title = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((text) => text.data ?? '')
      .firstWhere(
        (text) => text.startsWith('Shift #') && text.endsWith(' · open'),
      );
  if (includeSale) {
    await rehearseSale(tester);
    await waitForOperations(tester);
    expect(find.text(title), findsOneWidget);
  }
  for (var i = 0; i < 200; i++) {
    if (tester.widget<FilledButton>(close).onPressed != null) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(
    tester.widget<FilledButton>(close).onPressed,
    isNotNull,
    reason: 'Saved orders or operations must be resolved before closing.',
  );
  await tester.ensureVisible(close);
  await tester.tap(close);
  final countedCash = find.widgetWithText(TextFormField, 'Counted cash');
  await waitForControl(tester, countedCash);
  await tester.enterText(countedCash, includeSale ? (20 + rehearsalSalePrice).toStringAsFixed(2) : '20');
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  final closedTitle = find.text(title.replaceFirst(' · open', ' · closed'));
  await waitForControl(tester, closedTitle);
  final closedCard = find
      .ancestor(of: closedTitle, matching: find.byType(Card))
      .first;
  expect(
    find.descendant(
      of: closedCard,
      matching: find.text('Awaiting manager review'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: closedCard, matching: find.text('Difference')),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find
          .ancestor(
            of: find.descendant(
              of: closedCard,
              matching: find.text('Difference'),
            ),
            matching: find.byType(Wrap),
          )
          .first,
      matching: find.text('\$0.00'),
    ),
    findsOneWidget,
  );
  if (includeSale) {
    for (final entry in {
      'Cash sales': r'$' + rehearsalSalePrice.toStringAsFixed(2),
      'Expected drawer cash': r'$' + (20 + rehearsalSalePrice).toStringAsFixed(2),
    }.entries) {
      final row = find.ancestor(
        of: find.descendant(of: closedCard, matching: find.text(entry.key)),
        matching: find.byType(Wrap),
      );
      expect(
        find.descendant(of: row, matching: find.text(entry.value)),
        findsOneWidget,
      );
    }
  }
  expect(tester.takeException(), isNull);
  debugPrint(
    'PASS: $title closed with ${includeSale ? (20 + rehearsalSalePrice).toStringAsFixed(2) : '20.00'} counted and zero difference.',
  );
}

Future<void> rehearseSale(WidgetTester tester) async {
  const productId = int.fromEnvironment('SALE_PRODUCT_ID', defaultValue: 1);
  final salePrice = rehearsalSalePrice;
  expect(salePrice, greaterThan(0));
  final operationsContext = tester.element(find.byType(OperationsScreen));
  final container = ProviderScope.containerOf(operationsContext);
  expect(container.read(currentBranchProvider)?.id, 21);
  expect(
    container.read(cartControllerProvider).items,
    isEmpty,
    reason: 'Refusing to submit a pre-existing cart.',
  );
  await tester.tap(find.byTooltip('New takeaway order'));
  final productCard = find.byWidgetPredicate(
    (widget) => widget is ProductCard && widget.product.id == productId,
  );
  await waitForControl(tester, find.byType(GridView));
  await tester.scrollUntilVisible(productCard, 250,
      scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)));
  final product = tester.widget<ProductCard>(productCard).product;
  if (productId == 1) expect(product.name, 'Iced Latte');
  await tester.ensureVisible(productCard);
  if (product.hasVariants) {
    final variants = product.variants
        .where((v) => (v.price - salePrice).abs() < 0.001)
        .toList();
    expect(
      variants,
      isNotEmpty,
      reason: 'A variant matching the expected sale price is required.',
    );
    await tester.tap(productCard);
    final variant = find.widgetWithText(ListTile, variants.first.name);
    await waitForControl(tester, variant);
    await tester.tap(variant);
  } else {
    expect(product.price, salePrice, reason: 'Check the branch price before payment.');
    await tester.tap(productCard);
  }
  await tester.pump();
  final cart = container.read(cartControllerProvider);
  expect(cart.items, hasLength(1));
  expect(cart.items.single.quantity, 1);
  expect(cart.items.single.product.id, productId);
  expect(
    cart.total,
    salePrice,
    reason: 'Confirm the total before submitting payment.',
  );
  final review = find.text('Review Order').last;
  await tester.ensureVisible(review);
  await tester.tap(review);
  final amount = find.widgetWithText(TextField, 'Amount received');
  await waitForControl(tester, find.text('Takeaway order'));
  await tester.scrollUntilVisible(
    amount,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.enterText(amount, salePrice.toStringAsFixed(2));
  await tester.scrollUntilVisible(
    find.text('Confirm & Pay'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('Confirm & Pay'));
  await waitForControl(tester, find.text('Payment Successful'));
  debugPrint('PASS: Product #$productId cash sale completed for ${salePrice.toStringAsFixed(2)}.');
  await tester.ensureVisible(find.text('Back to Dashboard'));
  await tester.tap(find.text('Back to Dashboard'));
  await waitForControl(tester, find.byType(DashboardScreen));
  GoRouter.of(tester.element(find.byType(DashboardScreen))).go('/operations');
  await tester.pump();
}

Future<void> rehearseReview(WidgetTester tester) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OperationsScreen)),
  );
  expect(
    container.read(currentBranchProvider)?.id,
    21,
    reason: 'Review is restricted to rehearsal branch 21.',
  );
  const shiftId = int.fromEnvironment('REVIEW_SHIFT_ID');
  expect(shiftId, greaterThan(0), reason: 'Specify the rehearsal shift ID.');
  final title = find.text('Shift #$shiftId · closed');
  expect(title, findsOneWidget, reason: 'The target shift must be closed.');
  // The card disappears during API reloads. Keep this finder empty-safe so
  // waitForControl can poll until the reviewed card returns.
  Finder card() => find.ancestor(of: title, matching: find.byType(Card));
  void expectCash(String label, String value) {
    final row = find
        .ancestor(
          of: find.descendant(of: card(), matching: find.text(label)),
          matching: find.byType(Wrap),
        )
        .first;
    expect(
      find.descendant(of: row, matching: find.text(value)),
      findsOneWidget,
    );
  }

  expectCash('Opening cash', '\$20.00');
  expectCash('Expected drawer cash', '\$20.00');
  expectCash('Counted cash', '\$20.00');
  expectCash('Difference', '\$0.00');
  final reviewed = find.descendant(of: card(), matching: find.text('Reviewed'));
  if (reviewed.evaluate().isEmpty) {
    expect(
      find.descendant(
        of: card(),
        matching: find.text('Awaiting manager review'),
      ),
      findsOneWidget,
    );
    final review = find.descendant(
      of: card(),
      matching: find.widgetWithText(OutlinedButton, 'Confirm review'),
    );
    expect(
      review,
      findsOneWidget,
      reason: 'This account needs reports.view permission.',
    );
    await tester.ensureVisible(review);
    await tester.tap(review);
    await waitForControl(tester, find.text('Review shift'));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await waitForControl(tester, reviewed);
  }
  await tester.tap(find.byTooltip('Refresh'));
  await tester.pump();
  await waitForOperations(tester);
  expect(
    reviewed,
    findsOneWidget,
    reason: 'Review must persist after API refresh.',
  );
  expect(
    find.descendant(of: card(), matching: find.text('Awaiting manager review')),
    findsNothing,
  );
  expect(tester.takeException(), isNull);
  debugPrint('PASS: Shift #$shiftId manager review persisted after refresh.');
}

Future<void> rehearseStockCount(WidgetTester tester) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  final container = ProviderScope.containerOf(tester.element(find.byType(OperationsScreen)));
  expect(container.read(currentBranchProvider)?.id, 21);
  final repo = container.read(operationsRepositoryProvider);
  final pending = await tester.runAsync(repo.pending);
  expect(pending, isEmpty, reason: 'Resolve saved operations before the stock test.');
  final chip = find.widgetWithText(ChoiceChip, 'Stock counts');
  expect(chip, findsOneWidget, reason: 'Inventory access is required.');
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await waitForOperations(tester);
  Future<num> stock() async {
    final rows = await tester.runAsync(() => repo.get('/ingredients'));
    final matches = (rows as List).cast<Map>().where((row) => row['id'] == 11).toList();
    expect(matches, hasLength(1));
    expect(matches.single['name'], 'Coffee Bean');
    return num.parse('${matches.single['current_stock']}');
  }
  final before = await stock();
  if ((before - 49.980).abs() < 0.0001) {
    debugPrint('PASS: Coffee Bean is already at the rehearsal count 49.980; no change submitted.');
    return;
  }
  expect(before, closeTo(49.982, 0.0001),
      reason: 'Stock changed since the sale check. Refusing to overwrite it.');
  final card = find.ancestor(of: find.text('Coffee Bean'), matching: find.byType(Card));
  final count = find.descendant(of: card,
      matching: find.widgetWithText(OutlinedButton, 'Record count'));
  expect(count, findsOneWidget, reason: 'Inventory adjustment permission is required.');
  await tester.ensureVisible(count);
  await tester.tap(count);
  final quantity = find.widgetWithText(TextFormField, 'Actual counted quantity');
  await waitForControl(tester, quantity);
  await tester.enterText(quantity, '49.980');
  await tester.enterText(find.widgetWithText(TextFormField, 'Count note'),
      'Automated rehearsal stock count: 49.982 to 49.980');
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(AlertDialog).evaluate().isEmpty) break;
  }
  expect(find.byType(AlertDialog), findsNothing, reason: 'Stock count must finish saving.');
  await waitForOperations(tester);
  expect(await stock(), closeTo(49.980, 0.0001),
      reason: 'Count must persist in the API.');
  expect(await tester.runAsync(repo.pending), isEmpty,
      reason: 'Count must be confirmed, rather than only queued.');
  await tester.tap(find.byTooltip('Refresh'));
  await tester.pump();
  await waitForOperations(tester);
  expect(tester.takeException(), isNull);
  debugPrint('PASS: Coffee Bean stock count saved: 49.982 to 49.980 (difference -0.002).');
}

Future<void> rehearseAvailability(WidgetTester tester) async {
  expect(Env.apiBaseUrl, 'http://10.0.2.2:8001/api/v1');
  final context = tester.element(find.byType(OperationsScreen));
  final container = ProviderScope.containerOf(context);
  final router = GoRouter.of(context);
  expect(container.read(currentBranchProvider)?.id, 21);
  expect(container.read(cartControllerProvider).items, isEmpty);
  final api = container.read(apiClientProvider);
  final rows = await tester.runAsync(() =>
      container.read(operationsRepositoryProvider).get('/products'));
  final products = (rows as List).cast<Map>().where((p) => p['id'] == 6).toList();
  expect(products, hasLength(1), reason: 'Product #6 must initially be available.');
  expect(num.parse('${products.single['price']}'), 5);
  Future<Map> setAvailable(bool value) async {
    final response = await tester.runAsync(() => api.request(
      (dio) => dio.patch('/products/6', data: {
        'branches': [{'branch_id': 21, 'is_available': value, 'price_override': null}],
      }),
    ));
    final product = response!.data['data'] as Map;
    final branch = (product['branches'] as List).cast<Map>()
        .singleWhere((b) => b['branch_id'] == 21);
    expect(branch['is_available'], value);
    expect(branch['price_override'], isNull);
    return product;
  }
  Future<PosCatalogLoaded> refreshCatalog() async {
    await tester.runAsync(() =>
        container.read(posCatalogControllerProvider.notifier).refresh());
    await tester.pump();
    expect(container.read(cachedCatalogProvider), isFalse,
        reason: 'Availability must be checked against the live API.');
    final state = container.read(posCatalogControllerProvider);
    expect(state, isA<PosCatalogLoaded>());
    return state as PosCatalogLoaded;
  }
  try {
    await setAvailable(false);
    router.go('/pos');
    await tester.pump();
    final hidden = await refreshCatalog();
    expect(hidden.products.where((p) => p.id == 6), isEmpty,
        reason: 'Unavailable product must be excluded from the POS catalog.');
    expect(find.byWidgetPredicate(
        (w) => w is ProductCard && w.product.id == 6), findsNothing);
    expect(container.read(cartControllerProvider).items, isEmpty);
    debugPrint('PASS: Product #6 unavailable and excluded from the live POS catalog.');
  } finally {
    await setAvailable(true);
    router.go('/pos');
    await tester.pump();
    final restored = await refreshCatalog();
    expect(restored.products.where((p) => p.id == 6), hasLength(1),
        reason: 'Product #6 must return after availability is restored.');
    debugPrint('PASS: Product #6 availability restored; branch price override remains null.');
  }
  router.go('/operations');
  await tester.pump();
  await waitForOperations(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('existing signed-in session loads accessible operations views', (
    tester,
  ) async {
    const expectedApi = String.fromEnvironment(
      'SMOKE_EXPECTED_API',
      defaultValue: 'http://10.0.2.2:8001/api/v1',
    );
    expect(
      Env.apiBaseUrl,
      expectedApi,
      reason: 'Use the explicit rehearsal API endpoint for this smoke test.',
    );
    expect(
      Uri.parse(expectedApi).host,
      '10.0.2.2',
      reason: 'This test is restricted to the Android emulator host.',
    );

    // Keep the real stored session, API repositories, routing and UI. Suppress
    // automatic outbox uploads so this inspection cannot submit saved sales.
    runApp(
      ProviderScope(
        overrides: [orderSyncWorkerProvider.overrideWith((ref) {})],
        child: const TopCoffeeApp(),
      ),
    );
    await waitForHome(tester);

    final navigation = find.widgetWithText(ListTile, 'Daily Operations');
    if (navigation.evaluate().isEmpty) {
      final drawer = find.byTooltip('Open navigation menu');
      expect(
        drawer,
        findsOneWidget,
        reason: 'Daily Operations must be reachable from the app navigation.',
      );
      await tester.tap(drawer);
      await tester.pumpAndSettle();
    }
    expect(navigation, findsOneWidget);
    final shell = Scaffold.maybeOf(tester.element(navigation));
    await tester.ensureVisible(navigation);
    await tester.tap(navigation);
    await waitForOperations(tester);
    await tester.pumpAndSettle();
    if (shell != null && shell.mounted) {
      expect(
        shell.isDrawerOpen,
        isFalse,
        reason:
            'Navigation must close the drawer so operations controls can be used.',
      );
    }
    expect(find.widgetWithText(ChoiceChip, 'Shifts'), findsOneWidget);
    expect(
      find.text('No shifts for this branch yet.').evaluate().isNotEmpty ||
          find.textContaining('Shift #').evaluate().isNotEmpty,
      isTrue,
      reason: 'Shift records or the empty state must be displayed.',
    );
    debugPrint('PASS: Shifts loaded without a rendering or API error.');

    if (const bool.fromEnvironment('REHEARSE_AVAILABILITY')) {
      expect(const bool.fromEnvironment('REHEARSE_SALE') ||
          const bool.fromEnvironment('REHEARSE_SHIFT') ||
          const bool.fromEnvironment('REHEARSE_REVIEW') ||
          const bool.fromEnvironment('REHEARSE_STOCK_COUNT'), isFalse,
          reason: 'Run availability separately from other mutations.');
      await rehearseAvailability(tester);
    }
    if (const bool.fromEnvironment('REHEARSE_STOCK_COUNT')) {
      expect(const bool.fromEnvironment('REHEARSE_SALE') ||
          const bool.fromEnvironment('REHEARSE_SHIFT') ||
          const bool.fromEnvironment('REHEARSE_REVIEW'), isFalse,
          reason: 'Run the stock count separately from shift actions.');
      await rehearseStockCount(tester);
    }

    for (final section in ['Stock counts', 'Availability', 'Owner report']) {
      final chip = find.widgetWithText(ChoiceChip, section);
      if (chip.evaluate().isEmpty) {
        continue; // Respect this account's permissions.
      }
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await waitForOperations(tester);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      debugPrint('PASS: $section loaded without a rendering or API error.');
    }
    final shifts = find.widgetWithText(ChoiceChip, 'Shifts');
    await tester.ensureVisible(shifts);
    await tester.tap(shifts);
    await waitForOperations(tester);
    expect(tester.takeException(), isNull);
    expect(
      (const bool.fromEnvironment('REHEARSE_SHIFT') ||
              const bool.fromEnvironment('REHEARSE_SALE')) &&
          const bool.fromEnvironment('REHEARSE_REVIEW'),
      isFalse,
      reason: 'Run shift creation and existing shift review separately.',
    );
    if (const bool.fromEnvironment('REHEARSE_REVIEW')) {
      await rehearseReview(tester);
    }
    if (const bool.fromEnvironment('REHEARSE_SHIFT') ||
        const bool.fromEnvironment('REHEARSE_SALE')) {
      await rehearseShift(
        tester,
        includeSale: const bool.fromEnvironment('REHEARSE_SALE'),
      );
    }
  });
}
