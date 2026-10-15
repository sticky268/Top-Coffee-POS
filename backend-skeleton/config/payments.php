<?php

return [
    // Development rehearsals retain the existing manual bookkeeping methods.
    // Production starts cash-only until a real payment acceptance path is reviewed.
    'allowed_methods' => array_values(array_filter(array_map('trim', explode(',',
        env('POS_ALLOWED_PAYMENT_METHODS', env('APP_ENV') === 'production' ? 'cash' : 'cash,card,qr')
    )))),
];
