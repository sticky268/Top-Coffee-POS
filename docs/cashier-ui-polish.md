# Cashier UI polish

This pass retains the existing espresso/caramel palette and Material 3 themes. It improves the dashboard and POS catalog rather than changing checkout, payment, stock, branch permissions or API behavior.

- Dashboard statistics and shortcuts get predictable heights, adaptive column counts and larger section headings. Shortcut names can wrap to two lines. Content is bounded on wide displays.
- Branch selection has a visible field and a bounded desktop width. The inactive notifications button is removed; logout and branch selection remain available.
- Daily Operations and Print Queue belong to the Operations navigation group. Selecting Categories no longer also selects Products; nested POS routes still use the POS item.
- Recent-order amounts and status badges wrap beneath details on narrow or large-text displays. Long customer/table references can wrap without competing with a fixed trailing column.
- Product columns use the actual catalog pane width after the cart has taken its space. Tile height scales with text size, full names/prices are available in tooltips, image placeholders have a warm surface, and add/options icons explain the tap affordance.

Rendering tests exercise 360x800, 800x1280 and 1280x800 at normal/200% text in light/dark themes, long branch/product/customer names and a large amount. Interaction checks cover shortcut taps, product selection and one selected Categories entry. Narrow tablet catalog panes are tested separately. CI exports representative PNGs under the `cashier-ui-previews` artifact; these are component-fixture renders, not screenshots of a live customer's dashboard.

An existing order-list test's random UUID prefix could contain only digits, accidentally testing the numeric order-number filter. Its fixture now uses an explicit nonnumeric UUID prefix. Production filtering behavior is unchanged.

Before approving the look, open the app on the intended device and review dashboard, branch dropdown, recent orders, category navigation and POS product selection in both themes. Existing operation/layout/payment tests remain required. No backend migration is added by this pass.
