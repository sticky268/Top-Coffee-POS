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
        $user = $request->user();
        if ($user && ! $user->is_active) {
            return response()->json(['success' => false, 'message' => 'This account is inactive.'], 401);
        }
        if ($user) {
            // Fail closed on corrupted cross-business staff assignments.
            if ($user->branches()->where('business_id', '!=', $user->business_id)->exists()) {
                return response()->json(['success' => false, 'message' => 'Your branch assignments require administrator review.'], 403);
            }
            $selectedBranches = [];
            foreach (\Illuminate\Support\Arr::dot($request->all()) as $key => $selected) {
                if (preg_match('/(^|\.)branch_id$|(^|\.)branch_ids\.\d+$/', $key)
                    && is_scalar($selected) && filter_var($selected, FILTER_VALIDATE_INT) > 0) {
                    $selectedBranches[] = (int)$selected;
                }
            }
            if ($selectedBranches && \App\Models\Branch::withTrashed()->whereIn('id', $selectedBranches)
                ->where('business_id', '!=', $user->business_id)->exists()) {
                return response()->json(['success' => false, 'message' => 'You do not have access to that branch.'], 403);
            }
        }
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
