<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        RateLimiter::for('manager-pin', fn (Request $request) => [
            Limit::perMinute(15)->by('manager-pin-user:'.($request->user()?->id ?? 'guest')),
            Limit::perMinute(30)->by('manager-pin-ip:'.$request->ip()),
        ]);
        $loginThrottleResponse = function (Request $request, array $headers) {
            $seconds = max(1, (int) ($headers['Retry-After'] ?? 60));
            return response()->json(['success' => false, 'code' => 'LOGIN_RATE_LIMITED',
                'message' => 'Too many sign-in requests. Try again in '.$seconds.' seconds.',
                'retry_after' => $seconds], 429, $headers);
        };
        RateLimiter::for('pos-login', fn (Request $request) => [
            Limit::perMinute(30)->by('login-ip:'.$request->ip())->response($loginThrottleResponse),
            Limit::perMinute(10)->by('login-account:'.hash('sha256', strtolower(trim(is_string($request->input('email')) ? $request->input('email') : ''))))->response($loginThrottleResponse),
        ]);
    }
}
