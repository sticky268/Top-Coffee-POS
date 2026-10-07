<?php

use App\Http\Controllers\Api\V1\Auth\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\OrderController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\ExpenseController;
use App\Http\Controllers\Api\V1\ExpenseCategoryController;
use App\Http\Controllers\Api\V1\IngredientController;
use App\Http\Controllers\Api\V1\KitchenController;
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

    Route::post('/auth/login', [AuthController::class, 'login'])
        ->middleware('throttle:10,1');

    Route::middleware(['auth:sanctum', 'subscription.active'])->group(function () {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/me', [AuthController::class, 'me']);
        Route::get('/subscription', [SubscriptionController::class, 'show']);
        Route::get('/dashboard', [DashboardController::class, 'index']);
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
        Route::get('/branches/{branch}/kitchen-settings', [BranchController::class, 'kitchenSettings']);
        Route::patch('/branches/{branch}/kitchen-settings', [BranchController::class, 'updateKitchenSettings']);
        Route::patch('/branches/{branch}', [BranchController::class, 'update']);
        Route::delete('/branches/{branch}', [BranchController::class, 'destroy']);

        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::get('/users/{user}', [UserController::class, 'show']);
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
        Route::post('/orders/{id}/cancel', [OrderController::class, 'cancelHeld'])->whereNumber('id');
        Route::post('/orders', [OrderController::class, 'store']);
        Route::patch('/orders/{id}', [OrderController::class, 'update'])->whereNumber('id');
        Route::get('/orders', [OrderController::class, 'index']);
        Route::get('/orders/{id}', [OrderController::class, 'show'])->whereNumber('id');

        Route::get('/kitchen/tickets', [KitchenController::class, 'index']);
        Route::patch('/kitchen/tickets/{id}/status', [KitchenController::class, 'updateStatus'])->whereNumber('id');
        Route::post('/kitchen/tickets/{id}/acknowledge-cancellation', [KitchenController::class, 'acknowledgeCancellation'])->whereNumber('id');

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