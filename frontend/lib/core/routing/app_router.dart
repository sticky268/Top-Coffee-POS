import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/pos/presentation/checkout_screen.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/products/presentation/category_management_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

/// Bridges Riverpod's [authControllerProvider] to GoRouter's
/// [Listenable]-based `refreshListenable`, so GoRouter re-evaluates its
/// `redirect` callback whenever auth state changes — without recreating the
/// GoRouter instance itself (which would drop navigation history).
class _AuthRouterRefreshNotifier extends ChangeNotifier {
  _AuthRouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) => notifyListeners());
  }
}

final _authRouterRefreshProvider = Provider<_AuthRouterRefreshNotifier>((ref) {
  final notifier = _AuthRouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_authRouterRefreshProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final atSplash = state.matchedLocation == '/';
      final atLogin = state.matchedLocation == '/login';

      // Still restoring the session (or nothing has happened yet) — hold on
      // the splash screen rather than flashing the login screen first.
      if (auth is AuthInitial || auth is AuthLoading) {
        return atSplash ? null : '/';
      }

      // Not authenticated (or a login attempt failed) — every route except
      // login redirects here. This is what keeps /home, /pos, /orders,
      // /products, /inventory, and /reports protected: an unauthenticated
      // user hitting any of them bounces straight back to /login.
      if (auth is AuthUnauthenticated || auth is AuthError) {
        return atLogin ? null : '/login';
      }

      // Authenticated — never allow navigating back to splash/login.
      if (auth is AuthAuthenticated) {
        return (atSplash || atLogin) ? '/home' : null;
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const DashboardScreen()),
      // Quick-action destinations — pushed on top of /home (not replacing
      // it), so the back button returns to the dashboard. Placeholders
      // until their own phases build them out.
      GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
      GoRoute(path: '/pos/checkout', builder: (context, state) => const CheckoutScreen()),
      GoRoute(path: '/orders', builder: (context, state) => const OrdersScreen()),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) {
          final orderId = int.parse(state.pathParameters['id']!);
          return OrderDetailScreen(orderId: orderId);
        },
      ),
      GoRoute(path: '/products', builder: (context, state) => const ProductsScreen()),
      GoRoute(
  path: '/products/categories',
  builder: (context, state) => const CategoryManagementScreen(),
),
      GoRoute(
        path: '/products/form',
        builder: (context, state) {
          final args = state.extra as ProductFormArgs;
          return ProductFormScreen(args: args);
        },
      ),
      GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
      GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
    ],
  );
});
