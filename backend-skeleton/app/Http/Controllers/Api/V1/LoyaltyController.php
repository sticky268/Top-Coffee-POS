<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\LoyaltySetting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class LoyaltyController extends Controller
{
    /**
     * GET /api/v1/loyalty/settings
     */
    public function settings(Request $request)
    {
        if (! $request->user()->can('loyalty.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage loyalty',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $settings = LoyaltySetting::firstOrCreate(
            ['branch_id' => $branchId],
            [
                'is_enabled' => false,
                'points_per_currency_unit' => 1,
                'points_per_reward_currency_unit' => 100,
                'minimum_redeem_points' => 100,
                'redemption_enabled' => true,
                'expiration_months' => null,
            ]
        );

        return response()->json([
            'success' => true,
            'data' => $settings,
        ]);
    }

    /**
     * PATCH /api/v1/loyalty/settings
     */
    public function updateSettings(Request $request)
    {
        if (! $request->user()->can('loyalty.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage loyalty',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $validator = Validator::make($request->all(), [
            'is_enabled' => 'sometimes|boolean',
            'points_per_currency_unit' => 'sometimes|numeric|min:0|max:100000',
            'points_per_reward_currency_unit' => 'sometimes|numeric|min:0.0001|max:100000',
            'minimum_redeem_points' => 'sometimes|integer|min:0|max:4294967295',
            'redemption_enabled' => 'sometimes|boolean',
            'expiration_months' => 'sometimes|nullable|integer|min:1|max:120',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $settings = LoyaltySetting::firstOrCreate(
            ['branch_id' => $branchId],
            [
                'is_enabled' => false,
                'points_per_currency_unit' => 1,
                'points_per_reward_currency_unit' => 100,
                'minimum_redeem_points' => 100,
                'redemption_enabled' => true,
                'expiration_months' => null,
            ]
        );

        $settings->update($validator->validated());

        return response()->json([
            'success' => true,
            'message' => 'Loyalty settings updated successfully',
            'data' => $settings->fresh(),
        ]);
    }

    private function resolveBranchId(Request $request)
    {
        $user = $request->user();
        $branchId = $request->input('branch_id');

        if ($branchId !== null) {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }

            return (int) $branchId;
        }

        $branch = $user->branches()->wherePivot('is_primary', true)->first()
            ?? $user->branches()->first();

        if (! $branch) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is assigned to this user',
            ], 422);
        }

        return (int) $branch->id;
    }
}