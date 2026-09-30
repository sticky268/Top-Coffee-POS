<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SubscriptionController extends Controller
{
    /**
     * Get the authenticated business subscription details.
     */
    public function show(Request $request): JsonResponse
    {
        $business = $request->user()
            ->business()
            ->with('plan')
            ->first();

        if (! $business) {
            return response()->json([
                'success' => false,
                'message' => 'Your user account is not associated with a business.',
                'code' => 'BUSINESS_REQUIRED',
            ], 403);
        }

        $branchCount = $business->branches()->count();

        return response()->json([
            'success' => true,
            'data' => [
                'plan' => $business->plan ? [
                    'id' => $business->plan->id,
                    'name' => $business->plan->name,
                    'slug' => $business->plan->slug,
                    'branch_limit' => $business->plan->branch_limit,
                    'price' => $business->plan->price,
                    'billing_interval' => $business->plan->billing_interval,
                    'is_active' => $business->plan->is_active,
                ] : null,

                'branch_usage' => [
                    'current' => $branchCount,
                    'limit' => $business->plan?->branch_limit,
                    'remaining' => $business->plan
                        ? max($business->plan->branch_limit - $branchCount, 0)
                        : null,
                ],

                'subscription' => [
                    'status' => $business->subscriptionStatus(),
                    'started_at' => $business->started_at?->toISOString(),
                    'expires_at' => $business->expires_at?->toISOString(),
                    'is_active' => $business->subscriptionIsActive(),
                    'is_expired' => $business->subscriptionIsExpired(),
                    'can_modify' => $business->canModifyData(),
                ],
            ],
        ]);
    }
}