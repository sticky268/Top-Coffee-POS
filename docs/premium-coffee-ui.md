# Premium coffee UI

Visual redesign based on the verified open-order payment branch. Business logic, providers, repositories, API payloads and backend files are unchanged.

## Complete implementation

- `frontend/lib/core/theme/app_colors.dart`: central brand, semantic, receipt and dark palette.
- `frontend/lib/core/theme/app_theme.dart`: Material 3 light/dark themes and component styling.
- `frontend/lib/core/widgets/app_buttons.dart`: PrimaryButton, SecondaryButton, OutlinedButton, DangerButton, IconButton, PosActionButton and ActionSurface.
- All updated screens are complete source files in this branch, rather than partial patches.

## Design system

- Espresso #3E2723; caramel #C8A165; cream #FAF7F2.
- 14px control corners; 16px cards; 24px dialogs and sheets.
- Minimum 48px button targets; minimum 56px main POS actions.
- Native Material animated ripples, keyboard focus and disabled styling.
- Loading uses existing screen flags and an accessible 18px spinner; no new business state.
- Main layout spacing uses 8px increments, with 4px optical gaps retained for tight text/icon groupings.
- White light-mode cards and warm dark-mode surfaces with soft shadows.
- Receipt ink/paper colors remain print-oriented in both themes.

## Packages and font

No new packages are required. Inter is bundled under assets/fonts with its SIL Open Font License. The bundled font is subset to Latin, accents, punctuation, symbols and currencies; other scripts use Flutter/platform fallback fonts. Existing MaterialApp.router already uses AppTheme.light and AppTheme.dark, and follows system brightness.

## Replacement map

| Previous control | Shared control |
| --- | --- |
| FilledButton / ElevatedButton | PrimaryButton |
| TextButton | SecondaryButton |
| OutlinedButton | pos_ui.OutlinedButton |
| Destructive text/filled/outlined actions | DangerButton |
| Pay, confirm payment, review order and new order | PosActionButton |
| IconButton | pos_ui.IconButton |
| InkWell acting as a card/row button | ActionSurface |

The pos_ui alias avoids clashes with Flutter OutlinedButton and IconButton. Legacy styleFrom calls remain as style inputs; shared touch size, padding, radius and typography override old compact button geometry.

## Updated presentation files

- `frontend/lib/features/audit_log/presentation/audit_log_screen.dart`
- `frontend/lib/features/auth/presentation/login_screen.dart`
- `frontend/lib/features/branches/presentation/add_branch_screen.dart`
- `frontend/lib/features/branches/presentation/branches_screen.dart`
- `frontend/lib/features/branches/presentation/edit_branch_screen.dart`
- `frontend/lib/features/customers/presentation/add_customer_screen.dart`
- `frontend/lib/features/customers/presentation/customer_detail_screen.dart`
- `frontend/lib/features/customers/presentation/customers_screen.dart`
- `frontend/lib/features/customers/presentation/edit_customer_screen.dart`
- `frontend/lib/features/dashboard/presentation/dashboard_screen.dart`
- `frontend/lib/features/dashboard/presentation/widgets/dashboard_header.dart`
- `frontend/lib/features/dashboard/presentation/widgets/dashboard_navigation.dart`
- `frontend/lib/features/dashboard/presentation/widgets/order_status_presentation.dart`
- `frontend/lib/features/dashboard/presentation/widgets/quick_actions_grid.dart`
- `frontend/lib/features/dashboard/presentation/widgets/recent_orders_section.dart`
- `frontend/lib/features/dashboard/presentation/widgets/sales_overview_chart.dart`
- `frontend/lib/features/dashboard/presentation/widgets/stat_cards_grid.dart`
- `frontend/lib/features/expenses/presentation/add_expense_screen.dart`
- `frontend/lib/features/expenses/presentation/expenses_screen.dart`
- `frontend/lib/features/home/presentation/home_screen.dart`
- `frontend/lib/features/inventory/presentation/add_ingredient_screen.dart`
- `frontend/lib/features/inventory/presentation/edit_ingredient_screen.dart`
- `frontend/lib/features/inventory/presentation/inventory_movement_history_screen.dart`
- `frontend/lib/features/inventory/presentation/inventory_screen.dart`
- `frontend/lib/features/kds/presentation/kds_screen.dart`
- `frontend/lib/features/loyalty/presentation/loyalty_settings_screen.dart`
- `frontend/lib/features/orders/presentation/edit_order_screen.dart`
- `frontend/lib/features/orders/presentation/order_detail_screen.dart`
- `frontend/lib/features/orders/presentation/orders_screen.dart`
- `frontend/lib/features/orders/presentation/widgets/order_list_tile.dart`
- `frontend/lib/features/orders/presentation/widgets/order_status_helpers.dart`
- `frontend/lib/features/pos/presentation/checkout_screen.dart`
- `frontend/lib/features/pos/presentation/open_order_screen.dart`
- `frontend/lib/features/pos/presentation/pos_screen.dart`
- `frontend/lib/features/pos/presentation/select_table_screen.dart`
- `frontend/lib/features/pos/presentation/table_management_screen.dart`
- `frontend/lib/features/pos/presentation/widgets/cart_line_tile.dart`
- `frontend/lib/features/pos/presentation/widgets/cart_panel.dart`
- `frontend/lib/features/pos/presentation/widgets/product_card.dart`
- `frontend/lib/features/pos/presentation/widgets/product_grid.dart`
- `frontend/lib/features/pos/presentation/widgets/variant_selector_sheet.dart`
- `frontend/lib/features/products/presentation/category_management_screen.dart`
- `frontend/lib/features/products/presentation/product_form_screen.dart`
- `frontend/lib/features/products/presentation/products_screen.dart`
- `frontend/lib/features/products/presentation/recipe_editor_screen.dart`
- `frontend/lib/features/products/presentation/widgets/product_list_tile.dart`
- `frontend/lib/features/products/presentation/widgets/variant_editor_dialog.dart`
- `frontend/lib/features/purchasing/presentation/purchase_creation_screen.dart`
- `frontend/lib/features/purchasing/presentation/purchase_history_screen.dart`
- `frontend/lib/features/purchasing/presentation/suppliers_screen.dart`
- `frontend/lib/features/reports/presentation/reports_screen.dart`
- `frontend/lib/features/settings/presentation/about_screen.dart`
- `frontend/lib/features/settings/presentation/receipt_settings_screen.dart`
- `frontend/lib/features/settings/presentation/settings_screen.dart`
- `frontend/lib/features/splash/presentation/splash_screen.dart`
- `frontend/lib/features/staff/presentation/add_staff_screen.dart`
- `frontend/lib/features/staff/presentation/edit_staff_screen.dart`
- `frontend/lib/features/staff/presentation/staff_detail_screen.dart`
- `frontend/lib/features/staff/presentation/staff_screen.dart`
- `frontend/lib/features/subscription/presentation/subscription_screen.dart`

## Validation

Dart formatting/parsing and git diff whitespace checks passed. A source audit checked that API/action argument lists remained unchanged and no application, data, domain or backend files were edited. Font tables were read successfully. Five design-system tests cover touch sizes, callbacks, loading semantics, disabled controls and palette behavior. Flutter analysis and tests have not run in this environment.

Run on Windows:

```powershell
cd C:\Users\lokle\Projects\top-coffee-pos\top-coffee-pos
git fetch origin
git switch --track origin/codex/premium-coffee-ui
cd frontend
& "C:\Flutter\flutter\bin\flutter.bat" pub get
& "C:\Flutter\flutter\bin\flutter.bat" analyze
& "C:\Flutter\flutter\bin\flutter.bat" test
```

Review light/dark mode on a phone and a POS tablet, especially cart quantity controls, inventory action rows, table cards, payment dialogs and customer forms. The branch should remain a draft until runtime checks pass.
