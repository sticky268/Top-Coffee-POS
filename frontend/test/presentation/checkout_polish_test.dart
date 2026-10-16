import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/offline/order_outbox.dart';
import 'package:top_coffee_pos/core/branch/current_branch_provider.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/features/auth/data/auth_repository.dart';
import 'package:top_coffee_pos/features/auth/domain/auth_models.dart';
import 'package:top_coffee_pos/features/pos/application/cart_controller.dart';
import 'package:top_coffee_pos/features/pos/application/checkout_controller.dart';
import 'package:top_coffee_pos/features/pos/application/checkout_state.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/checkout_screen.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/cart_panel.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/checkout_summary.dart';

import 'package:top_coffee_pos/features/pos/presentation/widgets/phone_cart_bar.dart';

import 'ui_polish_test.dart' show savePreview;

class MockPosRepository extends Mock implements PosRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FixtureCheckoutController extends CheckoutController {
  FixtureCheckoutController(
    super.repository,
    super.ref,
    CheckoutState initial,
  ) {
    state = initial;
  }
}

const product = PosProduct(
  id: 1,
  name: 'Iced Caramel Latte with Oat Milk',
  sku: null,
  description: null,
  category: null,
  price: 3.50,
  variants: [],
);
const branch = BranchSummary(id: 21, name: 'Rehearsal', code: 'PP-01');

void main() {
  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  Future<({ProviderContainer container, MockPosRepository repository})> setup(
    WidgetTester tester, {
    required Widget child,
    Size size = const Size(360, 800),
    double scale = 1,
    bool dark = false,
    CheckoutState state = const CheckoutIdle(),
    GlobalKey? preview,
    bool cashOnly = false,
  }) async {
    final repo = MockPosRepository();
    final auth = MockAuthRepository();
    when(() => auth.hasStoredToken()).thenAnswer((_) async => cashOnly);
    if (cashOnly) {
      when(() => auth.getCurrentUser())
          .thenAnswer((_) async => const AuthenticatedUser(
                id: 1,
                name: 'Cashier',
                email: 'fixture@example.invalid',
                roles: ['cashier'],
                permissions: ['orders.create'],
                branches: [branch],
                allowedPaymentMethods: ['cash'],
              ));
    }
    final container = ProviderContainer(
      overrides: [
        posRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
        currentBranchProvider.overrideWith(
          (ref) => CurrentBranchNotifier(ref, listenToAuth: false)
            ..selectBranch(branch),
        ),
        checkoutControllerProvider.overrideWith(
          (ref) => FixtureCheckoutController(repo, ref, state),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(cartControllerProvider.notifier).addItem(product);
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
            child: RepaintBoundary(key: preview, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container: container, repository: repo);
  }

  testWidgets(
      'cash-only server configuration hides electronic checkout methods',
      (tester) async {
    await setup(tester, child: const CheckoutScreen(), cashOnly: true);
    final paymentFinder = find.byWidgetPredicate((widget) =>
        widget is CheckoutChoiceSelector &&
        widget.choices.any((choice) => choice.value == 'cash'));
    await tester.scrollUntilVisible(paymentFinder, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
    final payment = tester.widget<CheckoutChoiceSelector>(paymentFinder);
    expect(payment.choices.map((choice) => choice.value).toList(), ['cash']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nonfinite cash is rejected without a build exception',
      (tester) async {
    await setup(tester, child: const CheckoutScreen());
    final amount = find.widgetWithText(TextField, 'Amount received');
    await tester.scrollUntilVisible(amount, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
    for (final value in ['Infinity', '1e309', 'NaN', 'abc']) {
      await tester.enterText(amount, value);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid cash amount.'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find
                  .ancestor(
                      of: find.text('Complete & Print'),
                      matching: find.byType(FilledButton))
                  .first)
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short checkout with open keyboard has no layout overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await setup(tester,
        size: const Size(360, 320),
        child: const MediaQuery(
          data: MediaQueryData(
              size: Size(360, 320), viewInsets: EdgeInsets.only(bottom: 240)),
          child: CheckoutScreen(),
        ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('riel shortcut fills exact USD equivalent and preserves change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final built = await setup(tester, child: const CheckoutScreen());
    final riel = find.text('20,000៛ / \$5.00');
    await tester.scrollUntilVisible(riel, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
    await tester.pumpAndSettle();
    await tester.ensureVisible(riel);
    await tester.pumpAndSettle();
    expect(riel.hitTestable(), findsOneWidget);
    await tester.tap(riel);
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextField, 'Amount received');
    expect(tester.widget<TextField>(amount).controller!.text, '5.00');
    expect(find.text('Change equivalent: 6,000៛'), findsOneWidget);
    verifyZeroInteractions(built.repository);
  });

  testWidgets('phone cart expands for edits and returns to compact summary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final built = await setup(tester,
        child: const Scaffold(
          body: Column(children: [Expanded(child: SizedBox()), PhoneCartBar()]),
        ));
    expect(find.byKey(const ValueKey('phone-cart-summary')), findsOneWidget);
    expect(find.text('Order Summary'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('phone-cart-summary')));
    await tester.pumpAndSettle();
    expect(find.text('Order Summary'), findsOneWidget);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(
        built.container.read(cartControllerProvider).items.single.quantity, 2);
    await tester.tap(find.byTooltip('Close cart'));
    await tester.pumpAndSettle();
    expect(find.text('View cart · 2 items'), findsOneWidget);
    expect(find.text('\$7.00'), findsOneWidget);
    expect(find.text('Order Summary'), findsNothing);
    verifyZeroInteractions(built.repository);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'checkout choices, cash entry and change fit $size text $scale dark $dark',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final preview = GlobalKey();
            final built = await setup(
              tester,
              child: const CheckoutScreen(),
              size: size,
              scale: scale,
              dark: dark,
              preview: preview,
            );
            expect(tester.takeException(), isNull);
            final scrollable = find.byType(Scrollable).first;
            final amount = find.widgetWithText(TextField, 'Amount received');
            await tester.scrollUntilVisible(
              amount,
              350,
              scrollable: scrollable,
              maxScrolls: 50,
            );
            await tester.enterText(amount, '2.00');
            await tester.pumpAndSettle();
            expect(
              find.text('Cash received is below the total.'),
              findsOneWidget,
            );
            final pay = find.text('Complete & Print');
            await tester.scrollUntilVisible(
              pay,
              250,
              scrollable: scrollable,
              maxScrolls: 50,
            );
            final button = tester.widget<FilledButton>(
              find.ancestor(of: pay, matching: find.byType(FilledButton)).first,
            );
            expect(button.onPressed, isNull);
            final noPrint =
                find.widgetWithText(OutlinedButton, 'Complete Sale');
            expect(tester.widget<OutlinedButton>(noPrint).onPressed, isNull);
            await tester.scrollUntilVisible(
              find.text('Exact \$3.50'),
              -250,
              scrollable: scrollable,
              maxScrolls: 50,
            );
            await tester.tap(find.text('Exact \$3.50'));
            await tester.pumpAndSettle();
            expect((tester.widget<TextField>(amount)).controller!.text, '3.50');
            expect(
              find.text('Cash received is below the total.'),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
            if (size.width == 360 && scale == 1) {
              await tester.scrollUntilVisible(
                pay,
                180,
                scrollable: scrollable,
                maxScrolls: 50,
              );
              await tester.pumpAndSettle();
              await savePreview(
                tester,
                preview,
                'checkout-payment-360-${dark ? 'dark' : 'light'}',
              );
            }
            verifyZeroInteractions(built.repository);
          },
        );
      }
    }
  }

  testWidgets('split selection keeps payment inputs and does not submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final built = await setup(tester, child: const CheckoutScreen(), scale: 2);
    await tester.scrollUntilVisible(
      find.text('Split'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    await tester.ensureVisible(
      find
          .ancestor(
            of: find.text('Split'),
            matching: find.byType(OutlinedButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Split').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Split payment'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextField, 'Amount').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Amount'), findsWidgets);
    expect(find.text('Split payment'), findsOneWidget);
    final amounts = find.widgetWithText(TextField, 'Amount');
    await tester.enterText(amounts.first, '2.00');
    await tester.pumpAndSettle();
    final received = find.widgetWithText(TextField, 'Cash received');
    await tester.ensureVisible(received);
    await tester.pumpAndSettle();
    await tester.enterText(received, '5.00');
    await tester.pumpAndSettle();
    await tester.ensureVisible(amounts.last);
    await tester.pumpAndSettle();
    await tester.enterText(amounts.last, '1.50');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cash change'));
    await tester.pumpAndSettle();
    final cashChange = find.ancestor(
      of: find.text('Cash change'),
      matching: find.byType(CheckoutAmountRow),
    );
    expect(
      find.descendant(of: cashChange, matching: find.text('\$3.00')),
      findsOneWidget,
    );
    expect(find.text('Allocated'), findsOneWidget);
    expect(tester.takeException(), isNull);
    verifyZeroInteractions(built.repository);
  });

  testWidgets(
    'cart quantity, discount and clear cancellation preserve cart behavior',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = GlobalKey();
      final built = await setup(
        tester,
        child: const Scaffold(body: CartPanel()),
        scale: 2,
        preview: preview,
      );
      await tester.tap(find.byTooltip('Increase quantity'));
      await tester.pumpAndSettle();
      expect(
        built.container.read(cartControllerProvider).items.single.quantity,
        2,
      );
      await tester.tap(find.byTooltip('Decrease quantity'));
      await tester.pumpAndSettle();
      expect(
        built.container.read(cartControllerProvider).items.single.quantity,
        1,
      );
      await tester.scrollUntilVisible(
        find.text('Add discount'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add discount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0.50');
      await tester.ensureVisible(find.byTooltip('Apply discount'));
      await tester.tap(find.byTooltip('Apply discount'));
      await tester.pumpAndSettle();
      expect(built.container.read(cartControllerProvider).discountTotal, 0.50);
      expect(built.container.read(cartControllerProvider).total, 3.0);
      await tester.scrollUntilVisible(
        find.text('Clear Cart'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Clear Cart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(built.container.read(cartControllerProvider).items, hasLength(1));
      expect(tester.takeException(), isNull);
      await savePreview(tester, preview, 'cart-360-large-text');
      await tester.scrollUntilVisible(
        find.text('Review Order'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Review Order').hitTestable(), findsOneWidget);
      await savePreview(tester, preview, 'cart-total-360-large-text');
      verifyZeroInteractions(built.repository);
    },
  );

  for (final state in [
    const CheckoutQueued('621f0e83-69ca-4ad4-bff6-845d216e8024'),
    const CheckoutSuccess(
      OrderConfirmation(
        orderId: 42,
        orderNumber: 121,
        total: 1234567.89,
        paymentMethod: 'cash',
        tendered: 1234568,
        changeDue: 0.11,
      ),
    ),
  ]) {
    testWidgets('confirmation state ${state.runtimeType} fits large phone text',
        (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = GlobalKey();
      final built = await setup(
        tester,
        child: const CheckoutScreen(),
        state: state,
        scale: 2,
        preview: preview,
      );
      expect(tester.takeException(), isNull);
      if (state is CheckoutQueued) {
        expect(find.text('Order saved on this device'), findsOneWidget);
        expect(find.text('Payment Successful'), findsNothing);
      } else {
        expect(find.text('Order #000121'), findsOneWidget);
        expect(find.text('Order #000042'), findsNothing);
        expect(find.text('Payment Successful'), findsOneWidget);
      }
      await savePreview(
        tester,
        preview,
        'checkout-${state is CheckoutQueued ? 'pending' : 'success'}-large-text',
      );
      verifyZeroInteractions(built.repository);
    });
  }

  testWidgets('queued checkout requires confirmation before another sale',
      (tester) async {
    await setup(
      tester,
      child: const CheckoutScreen(),
      state: const CheckoutQueued('queued-sale'),
    );

    await tester.tap(find.text('Start Another Order'));
    await tester.pumpAndSettle();

    expect(find.text('Start another order?'), findsOneWidget);
    expect(
      find.textContaining('may charge the customer twice'),
      findsOneWidget,
    );
    expect(find.text('Start Separate Sale'), findsOneWidget);
    await tester.tap(find.text('Check Pending Order'));
    await tester.pumpAndSettle();
    expect(find.text('Start another order?'), findsNothing);
  });

  testWidgets(
      'matching sale cancellation keeps cart; explicit approval queues once',
      (tester) async {
    final built = await setup(tester, child: const CheckoutScreen());
    var calls = 0;
    when(() => built.repository.createOrder(
          items: any(named: 'items'),
          requestUuid: any(named: 'requestUuid'),
          acknowledgedPendingUuids: any(named: 'acknowledgedPendingUuids'),
          paymentMethod: any(named: 'paymentMethod'),
          orderType: any(named: 'orderType'),
          tendered: any(named: 'tendered'),
          discountTotal: any(named: 'discountTotal'),
          branchId: any(named: 'branchId'),
        )).thenAnswer((invocation) async {
      calls++;
      final acknowledged =
          invocation.namedArguments[#acknowledgedPendingUuids] as List<String>;
      if (!acknowledged.contains('original-sale')) {
        throw const UnresolvedOrderException('original-sale');
      }
      throw const QueuedOrderException('separate-sale');
    });
    final amount = find.widgetWithText(TextField, 'Amount received');
    await tester.scrollUntilVisible(amount, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
    await tester.enterText(amount, '5');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Complete Sale'));
    await tester.tap(find.text('Complete Sale'));
    // Submission stays busy behind the modal, so its spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Matching sale awaiting confirmation'), findsOneWidget);
    expect(calls, 1);
    expect(built.container.read(cartControllerProvider).items, hasLength(1));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(built.container.read(cartControllerProvider).items, hasLength(1));
    await tester.ensureVisible(find.text('Complete Sale'));
    await tester.tap(find.text('Complete Sale'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm Separate Sale'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(built.container.read(cartControllerProvider).items, isEmpty);
    expect(find.text('Order saved on this device'), findsOneWidget);
    expect(find.text('Payment Successful'), findsNothing);
  });
}
