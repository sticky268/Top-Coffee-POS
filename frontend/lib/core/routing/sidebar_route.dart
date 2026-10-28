import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Sidebar sections replace the workspace immediately. Detail pages retain
/// their normal push/pop transitions.
class SidebarRoute extends GoRoute {
  SidebarRoute({
    required super.path,
    required Widget Function(BuildContext, GoRouterState) builder,
    super.routes = const [],
  }) : super(
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: builder(context, state),
          ),
        );
}
