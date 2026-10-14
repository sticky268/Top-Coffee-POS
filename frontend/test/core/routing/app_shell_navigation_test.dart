import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:top_coffee_pos/core/routing/app_shell.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';

void main() {
  testWidgets('POS stays highlighted when cart and checkout are pushed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(selectedRoute: state.uri.path, child: child),
          routes: [
            for (final path in ['/home', '/pos', '/pos/checkout'])
              GoRoute(
                path: path,
                builder: (context, state) =>
                    Scaffold(body: Text('Screen: $path')),
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
          child:
              MaterialApp.router(theme: AppTheme.light, routerConfig: router)),
    );
    await tester.pumpAndSettle();

    bool selected(String label) => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .singleWhere(
          (tile) => tile.title is Text && (tile.title! as Text).data == label,
        )
        .selected;

    expect(selected('Dashboard'), isTrue);
    expect(selected('POS'), isFalse);
    unawaited(router.push<void>('/pos'));
    await tester.pumpAndSettle();
    expect(selected('POS'), isTrue);
    expect(selected('Dashboard'), isFalse);
    unawaited(router.push<void>('/pos/checkout'));
    await tester.pumpAndSettle();
    expect(selected('POS'), isTrue);
    expect(selected('Dashboard'), isFalse);
    router.pop();
    await tester.pumpAndSettle();
    expect(selected('POS'), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(selected('Dashboard'), isTrue);
    expect(selected('POS'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
