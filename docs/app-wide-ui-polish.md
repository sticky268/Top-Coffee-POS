# App polish review bundle

This branch includes the cart/checkout pass plus the next presentation pass for order history, Daily Operations, business management, login and settings.

- Order records display the branch receipt reference and keep status and amount below the main details. Detail items, totals, metadata and the restricted adjustment action fit narrow screens and large text. Receipt actions and the order ID used for API requests remain unchanged.
- A shared PageContent widget constrains existing management lists to 1000px and forms/details to 800px, retaining their existing scroll, refresh and pagination behavior. Reports and receipt settings retain a 1200px workspace; receipt settings stack their preview at large text sizes.
- Customer, staff, branch, supplier and product records show full names and contact details instead of compressing them beside trailing totals/statuses. Product disable permissions and subscription restrictions remain unchanged. Inventory heading actions wrap, and Add Expense remains reachable through a labelled icon in the app bar.
- Report range choices wrap, summary cards use natural heights, and long monetary totals stay on one line. Payment methods, order types and top products have full-width summaries.
- Daily Operations labels and values adapt to narrow widths and large text; branch selection, permission gates, pending UUIDs and retry callbacks are retained.
- Login has clearer branding and welcome text, matched field borders and no email/password autocorrection. Validation, focus movement and authentication remain unchanged. Settings use the same readable record layout.

Validation includes phone/tablet, both themes and normal/200% text; receipt identity differs deliberately from the database ID. Tests verify row taps, read-only product restrictions, login validation, historical detail scrolling and the original pending-operation retry without submitting new writes. The optional rehearsal uses DetailValue finders for shift balances so it continues to test the values after the row layout change. CI exports representative PNG previews for inspection.

This is a consistent layout pass, not a redesign of every feature workflow. Physical printer output and the user's final device review are still useful before merge. No backend schema, tenancy, business controls, payment payloads or receipt renderer changes are part of this pass.
