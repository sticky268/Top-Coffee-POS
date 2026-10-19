import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import 'package:top_coffee_pos/features/pos/data/pos_repository.dart';

void main() {
  for (final width in [390.0, 800.0, 1200.0]) {
    testWidgets('one page toolbar retains menu and back at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 30);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final router = GoRouter(initialLocation: '/orders', routes: [
        ShellRoute(
          builder: (_, state, child) =>
              AppShell(selectedRoute: state.uri.path, child: child),
          routes: [
            for (final path in ['/orders', '/orders/1'])
              GoRoute(
                path: path,
                builder: (_, __) => Scaffold(
                  appBar: PageAppBar(title: Text(path)),
                  body: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      if (width < 900) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer).hitTestable(), findsOneWidget);
        tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
        await tester.pumpAndSettle();
      } else {
        expect(find.byTooltip('Open navigation menu'), findsNothing);
      }
      if (width < 900) {
        final container =
            ProviderScope.containerOf(tester.element(find.byType(AppShell)));
        container.read(cachedCatalogProvider.notifier).state = true;
        await tester.pumpAndSettle();
        expect(
            tester.getTopLeft(find.textContaining('Using saved catalog.')).dy,
            greaterThanOrEqualTo(30));
        expect(find.byType(AppBar), findsOneWidget);
      }
      unawaited(router.push<void>('/orders/1'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('/orders'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
