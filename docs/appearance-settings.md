# Appearance settings

Settings → Appearance offers Light, Dark, and Use device setting. The default follows the device. An explicit choice updates the whole app immediately and is stored locally under `appearance.theme_mode`; it applies to all staff and branches using that installation.

Startup loads the saved choice before rendering the app. Unknown or unreadable preferences fall back to the device setting. A failed write restores the previous selection and displays a retryable error. Controls are temporarily disabled while saving so concurrent writes cannot reorder preferences. Changing appearance reuses the current router and authentication state.

Regression coverage exercises preference round trips, unrelated preference retention, unknown values, concurrent writes, failure recovery, the actual app's saved first-frame mode, form/router retention, and system-brightness changes. Settings widget tests cover phone/tablet, light/dark, normal/200% text, saving through the visible controls, and scrolling to existing receipt settings. CI exports appearance previews with the other cashier UI images.
