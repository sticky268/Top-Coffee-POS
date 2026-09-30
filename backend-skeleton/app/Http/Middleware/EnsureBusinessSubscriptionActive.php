<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureBusinessSubscriptionActive
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->isMethodSafe()) {
            $business = $request->user()?->business;

            if ($business && $business->subscriptionStatus() === 'expired') {
                return response()->json([
                    'success' => false,
                    'message' => 'Your subscription has expired. Please renew your plan to continue.',
                    'code' => 'SUBSCRIPTION_EXPIRED',
                ], 403);
            }

            if ($business && $business->subscriptionStatus() === 'suspended') {
                return response()->json([
                    'success' => false,
                    'message' => 'Your business account is suspended. Please contact the administrator.',
                    'code' => 'BUSINESS_SUSPENDED',
                ], 403);
            }
        }

        return $next($request);
    }
}