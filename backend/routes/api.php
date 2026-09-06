<?php

use App\Http\Controllers\Api\V1\Auth\AuthController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    Route::post('/auth/login', [AuthController::class, 'login'])
        ->middleware('throttle:10,1'); // 10 attempts/minute

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/me', [AuthController::class, 'me']);

        // Phase 3+ will add: users, branches CRUD, products, orders, inventory, etc.
        // Deliberately not built here — Phase 2 is foundation only.
    });
});
