<?php

use App\Http\Controllers\Api\V1\Auth\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\OrderController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\ExpenseController;
use App\Http\Controllers\Api\V1\ExpenseCategoryController;
use App\Http\Controllers\Api\V1\IngredientController;
use App\Http\Controllers\Api\V1\UnitController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\RestaurantTableController;
use App\Http\Controllers\Api\V1\RecipeController;
use App\Http\Controllers\Api\V1\SupplierController;
use App\Http\Controllers\Api\V1\PurchaseController;
use App\Http\Controllers\Api\V1\ReportsController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\UserController;
use App\Http\Controllers\Api\V1\AuditLogController;
use App\Http\Controllers\Api\V1\LoyaltyController;
use App\Http\Controllers\Api\V1\BranchController;
use App\Http\Controllers\Api\V1\SubscriptionController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('/operations/health', \App\Http\Controllers\OperationsHealthController::class)->middleware('throttle:30,1');

    Route::post('/auth/login', [AuthController::class, 'login'])
        ->middleware('throttle:pos-login');

    // Losing subscription write access must never prevent session revocation.
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/auth/manager-pin', [\App\Http\Controllers\Api\V1\Auth\ManagerPinController::class, 'show']);
        Route::post('/auth/manager-pin', [\App\Http\Controllers\Api\V1\Auth\ManagerPinController::class, 'store'])->middleware('throttle:manager-pin');
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/sessions', [AuthController::class, 'sessions']);
        Route::delete('/auth/sessions/{session}', [AuthController::class, 'revokeSession'])->whereNumber('session');
        Route::post('/auth/logout-all', [AuthController::class, 'logoutAll']);
    });

    Route::middleware(['auth:sanctum', 'subscription.active'])->group(function () {
        Route::get('/auth/me', [AuthController::class, 'me']);
        Route::post('/cash-drawer-events', [\App\Http\Controllers\Api\V1\CashDrawerEventController::class, 'store'])->middleware('throttle:120,1');
        Route::get('/shifts', [\App\Http\Controllers\Api\V1\ShiftController::class, 'index']);
        Route::post('/shifts', [\App\Http\Controllers\Api\V1\ShiftController::class, 'open']);
        Route::post('/shifts/{id}/movements', [\App\Http\Controllers\Api\V1\ShiftController::class, 'movement'])->whereNumber('id');
        Route::post('/shifts/{id}/close', [\App\Http\Controllers\Api\V1\ShiftController::class, 'close'])->whereNumber('id');
        Route::post('/shifts/{id}/review', [\App\Http\Controllers\Api\V1\ShiftController::class, 'review'])->whereNumber('id');
        Route::get('/orders/{id}/financials', [\App\Http\Controllers\Api\V1\PaymentAdjustmentController::class, 'show'])->whereNumber('id');
        Route::post('/orders/{id}/refund', [\App\Http\Controllers\Api\V1\PaymentAdjustmentController::class, 'refund'])->whereNumber('id')->middleware(['throttle:manager-pin', \App\Http\Middleware\RequireManagerPin::class.':refund']);
        Route::post('/orders/{id}/additional-charge', [\App\Http\Controllers\Api\V1\PaymentAdjustmentController::class, 'charge'])->whereNumber('id');
        Route::post('/stock/count', [\App\Http\Controllers\Api\V1\StockOperationsController::class, 'count']);
        Route::post('/stock/transfer', [\App\Http\Controllers\Api\V1\StockOperationsController::class, 'transfer']);
        Route::get('/products/availability', [\App\Http\Controllers\Api\V1\OperationsReportController::class, 'availability']);
        Route::get('/reports/operations', [\App\Http\Controllers\Api\V1\OperationsReportController::class, 'report']);
        Route::get('/subscription', [SubscriptionController::class, 'show']);
        Route::get('/dashboard', [DashboardController::class, 'index']);
        Route::get('/reports/sales', [\App\Http\Controllers\Api\V1\SalesReportsController::class, 'index']);
        Route::get('/reports', [ReportsController::class, 'index']);
        Route::get('/units', [UnitController::class, 'index']);

        Route::get('/customers', [CustomerController::class, 'index']);
        Route::post('/customers', [CustomerController::class, 'store']);
        Route::get('/customers/{customer}', [CustomerController::class, 'show']);
        Route::patch('/customers/{customer}', [CustomerController::class, 'update']);
        Route::delete('/customers/{customer}', [CustomerController::class, 'destroy']);
        Route::get('/customers/{customer}/orders', [CustomerController::class, 'orders']);
        Route::get('/customers/{customer}/loyalty', [CustomerController::class, 'loyalty']);
        Route::post('/customers/{customer}/loyalty/adjust', [CustomerController::class, 'adjustLoyalty']);

        Route::get('/loyalty/settings', [LoyaltyController::class, 'settings']);
        Route::patch('/loyalty/settings', [LoyaltyController::class, 'updateSettings']);

        Route::get('/branches', [BranchController::class, 'index']);
        Route::post('/branches', [BranchController::class, 'store']);
        Route::get('/branches/{branch}', [BranchController::class, 'show']);
        Route::patch('/branches/{branch}', [BranchController::class, 'update']);
        Route::delete('/branches/{branch}', [BranchController::class, 'destroy']);

        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::get('/users/{user}', [UserController::class, 'show']);
        Route::post('/users/{user}/revoke-sessions', [UserController::class, 'revokeSessions'])->middleware('throttle:20,1');
        Route::patch('/users/{user}', [UserController::class, 'update']);
        Route::delete('/users/{user}', [UserController::class, 'destroy']);
        Route::get('/audit-logs', [AuditLogController::class, 'index']);

        Route::get('/categories', [CategoryController::class, 'index']);
        Route::post('/categories', [CategoryController::class, 'store']);
        Route::patch('/categories/{category}', [CategoryController::class, 'update']);
        Route::delete('/categories/{category}', [CategoryController::class, 'destroy']);

        Route::get('/products', [ProductController::class, 'index']);
        Route::post('/products', [ProductController::class, 'store']);
        Route::patch('/products/{product}', [ProductController::class, 'update']);
        Route::get('/products/{product}/recipe', [RecipeController::class, 'show']);
        Route::put('/products/{product}/recipe', [RecipeController::class, 'update']);

        Route::get('/tables', [RestaurantTableController::class, 'index']);

        Route::get('/expense-categories', [ExpenseCategoryController::class, 'index']);
        Route::get('/expenses', [ExpenseController::class, 'index']);
        Route::post('/expenses', [ExpenseController::class, 'store']);
        Route::get('/expenses/summary', [ExpenseController::class, 'summary']);
        Route::get('/expenses/{id}', [ExpenseController::class, 'show'])->whereNumber('id');
        Route::patch('/expenses/{id}', [ExpenseController::class, 'update'])->whereNumber('id');
        Route::delete('/expenses/{id}', [ExpenseController::class, 'destroy'])->whereNumber('id');
        Route::post('/tables', [RestaurantTableController::class, 'store']);
        Route::patch('/tables/{table}', [RestaurantTableController::class, 'update']);
        Route::delete('/tables/{table}', [RestaurantTableController::class, 'destroy']);

        Route::post('/orders/hold', [OrderController::class, 'hold']);
        Route::patch('/orders/{id}/hold', [OrderController::class, 'updateHeld'])->whereNumber('id');
        Route::post('/orders/{id}/pay', [OrderController::class, 'payHeld'])->whereNumber('id');
        Route::post('/orders/{id}/cancel', [OrderController::class, 'cancelHeld'])->whereNumber('id')->middleware(['throttle:manager-pin', \App\Http\Middleware\RequireManagerPin::class.':void']);
        Route::post('/orders', [OrderController::class, 'store']);
        Route::patch('/orders/{id}', [OrderController::class, 'update'])->whereNumber('id');
        Route::get('/orders', [OrderController::class, 'index']);
        Route::get('/orders/{id}', [OrderController::class, 'show'])->whereNumber('id');
        Route::get('/ingredients/{id}/products', \App\Http\Controllers\Api\V1\IngredientImpactController::class)->whereNumber('id');
        Route::get('/ingredients', [IngredientController::class, 'index']);
        Route::post('/ingredients', [IngredientController::class, 'store']);
        Route::patch('/ingredients/{id}', [IngredientController::class, 'update'])->whereNumber('id');
        Route::delete('/ingredients/{id}', [IngredientController::class, 'destroy'])->whereNumber('id');
        Route::get('/ingredients/{id}/movements', [IngredientController::class, 'movements'])->whereNumber('id');
        Route::post('/ingredients/{id}/movements', [IngredientController::class, 'recordMovement'])->whereNumber('id');
        Route::get('/suppliers', [SupplierController::class, 'index']);
        Route::post('/suppliers', [SupplierController::class, 'store']);
        Route::patch('/suppliers/{id}', [SupplierController::class, 'update'])->whereNumber('id');
        Route::delete('/suppliers/{id}', [SupplierController::class, 'destroy'])->whereNumber('id');

        Route::get('/purchases', [PurchaseController::class, 'index']);
        Route::post('/purchases', [PurchaseController::class, 'store']);
    });
});