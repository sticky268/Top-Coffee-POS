import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';

void main() {
  for (final width in [390.0, 800.0, 1200.0]) {
    testWidgets('one page toolbar retains menu and back at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
