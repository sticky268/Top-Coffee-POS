# Cart and checkout polish

This pass retains the coffee palette and focuses on the cashier's review/payment flow.

- Cart items separate names/variants and unit-price information from a bordered quantity stepper and line total. Quantity callbacks and line keys are unchanged.
- Header and discount controls wrap in narrow panels. Short or large-text carts scroll to the existing Review Order action. Subtotal, discount and total continue to use CartState values; a tinted total card adds hierarchy.
- Checkout has an 800px reading-width limit and responsive order/payment choices. The values remain takeaway/dine_in and cash/card/qr/split. Choices and entry are disabled during submission as before.
- Read-only order lines and currency summaries wrap at large text sizes. Cash entry explains change calculation, uses the existing short-cash condition for error styling, and labels the total-matching shortcut Exact. Calculations, optional empty-cash behavior and the quick amount values remain unchanged.
- Confirm & Pay labels wrap; its enabling rule, submission callback and payload are unchanged. Split validation, saved orders and receipt actions are retained. The split preview distinguishes allocated amounts from money received and displays cash change as received cash minus its allocated portion; this display does not change submitted amounts.
- Success displays the server-confirmed receipt number, total paid, cash received and change using responsive summaries. A device-saved request remains a distinct pending-confirmation view with its reference and warning; it scrolls on small/large-text screens and never claims payment success.

Rendering/interaction tests exercise 360x800, 800x1280 and 1280x800, normal/200% text and both themes. They cover short cash and disabled confirmation, exact cash selection, split inputs, quantity/discount updates, clear-cart cancellation and distinct pending/success fixtures. Mock repositories verify these presentation checks submit no sale. Existing controller/payment tests and Android workflow remain required. CI's cashier-ui-previews artifact includes representative rendered checkout/cart fixtures for visual inspection; these are not live customer transactions.

No backend or migration changes. Before merge, review cart controls, total hierarchy, payment choices, cash/change, split payment and confirmation on the intended emulator/device.
