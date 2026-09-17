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
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    Route::post('/auth/login', [AuthController::class, 'login'])
        ->middleware('throttle:10,1');

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/me', [AuthController::class, 'me']);
        Route::get('/dashboard', [DashboardController::class, 'index']);
        Route::get('/units', [UnitController::class, 'index']);

        Route::get('/categories', [CategoryController::class, 'index']);
        Route::post('/categories', [CategoryController::class, 'store']);

        Route::get('/products', [ProductController::class, 'index']);
        Route::post('/products', [ProductController::class, 'store']);
        Route::patch('/products/{product}', [ProductController::class, 'update']);
        Route::get('/products/{product}/recipe', [RecipeController::class, 'show']);
        Route::put('/products/{product}/recipe', [RecipeController::class, 'update']);

        Route::get('/tables', [RestaurantTableController::class, 'index']);

        Route::get('/expense-categories', [ExpenseCategoryController::class, 'index']);
        Route::get('/expenses', [ExpenseController::class, 'index']);
        Route::post('/expenses', [ExpenseController::class, 'store']);
        Route::get('/expenses/{id}', [ExpenseController::class, 'show'])->whereNumber('id');
        Route::patch('/expenses/{id}', [ExpenseController::class, 'update'])->whereNumber('id');
        Route::post('/tables', [RestaurantTableController::class, 'store']);
        Route::patch('/tables/{table}', [RestaurantTableController::class, 'update']);
        Route::delete('/tables/{table}', [RestaurantTableController::class, 'destroy']);

        Route::post('/orders/hold', [OrderController::class, 'hold']);
        Route::patch('/orders/{id}/hold', [OrderController::class, 'updateHeld'])->whereNumber('id');
        Route::post('/orders/{id}/pay', [OrderController::class, 'payHeld'])->whereNumber('id');
        Route::post('/orders', [OrderController::class, 'store']);
        Route::get('/orders', [OrderController::class, 'index']);
        Route::get('/orders/{id}', [OrderController::class, 'show'])->whereNumber('id');

        Route::get('/ingredients', [IngredientController::class, 'index']);
        Route::post('/ingredients', [IngredientController::class, 'store']);
        Route::patch('/ingredients/{id}', [IngredientController::class, 'update'])->whereNumber('id');
        Route::get('/ingredients/{id}/movements', [IngredientController::class, 'movements'])->whereNumber('id');
        Route::post('/ingredients/{id}/movements', [IngredientController::class, 'recordMovement'])->whereNumber('id');
        Route::get('/suppliers', [SupplierController::class, 'index']);
        Route::post('/suppliers', [SupplierController::class, 'store']);
        Route::patch('/suppliers/{id}', [SupplierController::class, 'update'])->whereNumber('id');
        Route::delete('/suppliers/{id}', [SupplierController::class, 'destroy'])->whereNumber('id');

        Route::post('/purchases', [PurchaseController::class, 'store']);
    });
});