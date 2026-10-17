<?php

use App\Http\Middleware\EnsureBusinessSubscriptionActive;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        // API clients and browser probes must receive 401 JSON even without
        // an Accept header. Do not resolve the web login route for API paths.
        $middleware->redirectGuestsTo(function (Request $request) {
            return $request->is('api/*') ? null : route('login');
        });
        $middleware->alias([
            'subscription.active' => EnsureBusinessSubscriptionActive::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions) {
        $exceptions->dontFlash(['current_password', 'pin', 'pin_confirmation']);
        $exceptions->shouldRenderJsonWhen(function ($request, $input) {
            return $request->is('api/*') || $request->expectsJson();
        });
    })
    ->create();