import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/audit_log/presentation/audit_log_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/customers/presentation/add_customer_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/edit_customer_screen.dart';
import '../../features/customers/application/customer_detail_state.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/expenses/presentation/add_expense_screen.dart';

import 'package:top_coffee_pos/features/inventory/presentation/inventory_screen.dart';

import '../../features/inventory/presentation/add_ingredient_screen.dart';
import '../../features/inventory/presentation/edit_ingredient_screen.dart';
import '../../features/inventory/presentation/inventory_movement_history_screen.dart';
import '../../features/inventory/domain/inventory_models.dart';
import '../../features/orders/presentation/edit_order_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/loyalty/presentation/loyalty_settings_screen.dart';
import '../../features/pos/presentation/checkout_screen.dart';

import '../../features/pos/presentation/pos_screen.dart';
import '../../features/pos/domain/pos_models.dart';
import '../../features/pos/presentation/select_table_screen.dart';
import '../../features/pos/presentation/open_order_screen.dart';

import '../../features/pos/presentation/table_management_screen.dart';
import '../../features/products/presentation/category_management_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/purchasing/presentation/purchase_history_screen.dart';
import '../../features/purchasing/presentation/suppliers_screen.dart';
import '../../features/purchasing/presentation/purchase_creation_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/receipt_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/about_screen.dart';
import '../../features/subscription/presentation/subscription_screen.dart';

import 'package:top_coffee_pos/features/staff/presentation/staff_screen.dart';
import 'package:top_coffee_pos/features/staff/presentation/staff_detail_screen.dart';
import 'package:top_coffee_pos/features/staff/presentation/add_staff_screen.dart';
import 'package:top_coffee_pos/features/branches/presentation/branches_screen.dart';
import 'package:top_coffee_pos/features/branches/presentation/add_branch_screen.dart';
import 'package:top_coffee_pos/features/branches/presentation/edit_branch_screen.dart';

import '../../features/splash/presentation/splash_screen.dart';
import 'app_shell.dart';

final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Bridges Riverpod's [authControllerProvider] to GoRouter's
/// [Listenable]-based `refreshListenable`, so GoRouter re-evaluates its
/// `redirect` callback whenever auth state changes.
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
    observers: [appRouteObserver],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final atSplash = state.matchedLocation == '/';
      final atLogin = state.matchedLocation == '/login';

      if (auth is AuthInitial || auth is AuthLoading) {
        return atSplash ? null : '/';
      }

      if (auth is AuthUnauthenticated || auth is AuthError) {
        return atLogin ? null : '/login';
      }

      if (auth is AuthAuthenticated) {
        return (atSplash || atLogin) ? '/home' : null;
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(selectedRoute: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/audit-log',
            builder: (context, state) => const AuditLogScreen(),
          ),          GoRoute(
            path: '/pos',
            builder: (context, state) => PosScreen(
              initialTable: state.extra is PosTable
                  ? state.extra as PosTable
                  : null,
            ),
          ),
          GoRoute(
            path: '/pos/checkout',
            builder: (context, state) => CheckoutScreen(
              initialTable: state.extra is PosTable
                  ? state.extra as PosTable
                  : null,
            ),
          ),
          GoRoute(
            path: '/pos/select-table',
            builder: (context, state) => const SelectTableScreen(),
          ),
          GoRoute(
            path: '/pos/open-order/:id',
            builder: (context, state) {
              final orderId = int.parse(state.pathParameters['id']!);
              return OpenOrderScreen(orderId: orderId);
            },
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/orders/:id/edit',
            builder: (context, state) {
              final orderId = int.parse(state.pathParameters['id']!);
              return EditOrderScreen(orderId: orderId);
            },
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (context, state) {
              final orderId = int.parse(state.pathParameters['id']!);
              return OrderDetailScreen(orderId: orderId);
            },
          ),
          GoRoute(
            path: '/staff',
            builder: (context, state) => const StaffScreen(),
          ),
          GoRoute(
            path: '/staff/add',
            builder: (context, state) => const AddStaffScreen(),
          ),
          GoRoute(
            path: '/staff/:id',
            builder: (context, state) {
              final staffId = int.parse(state.pathParameters['id']!);
              return StaffDetailScreen(staffId: staffId);
            },
          ),
          GoRoute(
            path: '/branches',
            builder: (context, state) => const BranchesScreen(),
          ),
          GoRoute(
            path: '/branches/add',
            builder: (context, state) => const AddBranchScreen(),
          ),
          GoRoute(
            path: '/branches/:id',
            builder: (context, state) {
              final branchId = int.parse(state.pathParameters['id']!);
              return EditBranchScreen(branchId: branchId);
            },
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const AddCustomerScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final customerId = int.parse(state.pathParameters['id']!);

                  return CustomerDetailScreen(customerId: customerId);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) {
                      final customer = state.extra as CustomerDetailLoaded;

                      return EditCustomerScreen(
                        customerId: int.parse(state.pathParameters['id']!),
                        customer: customer,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/loyalty',
            builder: (context, state) => const LoyaltySettingsScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsScreen(),
          ),
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
          GoRoute(
            path: '/tables',
            builder: (context, state) => const TableManagementScreen(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const AddIngredientScreen(),
              ),
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final ingredient = state.extra as InventoryIngredient;
                  return EditIngredientScreen(ingredient: ingredient);
                },
              ),
              GoRoute(
                path: 'history',
                builder: (context, state) {
                  final ingredient = state.extra as InventoryIngredient;
                  return InventoryMovementHistoryScreen(ingredient: ingredient);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersScreen(),
          ),
          GoRoute(
            path: '/purchases',
            builder: (context, state) => const PurchaseHistoryScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const PurchaseCreationScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/receipt',
            builder: (context, state) => const ReceiptSettingsScreen(),
          ),          GoRoute(
            path: '/settings/about',
            builder: (context, state) => const AboutScreen(),
          ),
          GoRoute(
            path: '/settings/subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/expenses',
            builder: (context, state) => const ExpensesScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const AddExpenseScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
