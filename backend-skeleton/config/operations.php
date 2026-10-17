<?php

return [
    'health_token' => env('POS_HEALTH_TOKEN'),
    // Operational warning thresholds; not fraud decisions or per-user verdicts.
    'window_minutes' => (int) env('POS_HEALTH_WINDOW_MINUTES', 5),
    'failed_login_limit' => (int) env('POS_HEALTH_FAILED_LOGIN_LIMIT', 20),
    'refund_limit' => (int) env('POS_HEALTH_REFUND_LIMIT', 10),
    'cancel_limit' => (int) env('POS_HEALTH_CANCEL_LIMIT', 10),
    'minimum_free_bytes' => (int) env('POS_HEALTH_MINIMUM_FREE_BYTES', 536870912),
];
