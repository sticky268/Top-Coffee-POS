<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Category;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CategoryController extends Controller
{
    /**
     * GET /api/v1/categories
     *
     * Returns active categories visible to the authenticated user's branch
     * context: global categories (branch_id IS NULL) plus any categories
     * specific to that branch — matching the "null = global category"
     * convention already established in the categories migration.
     *
     * No specific permission is required beyond being authenticated
     * (auth:sanctum): browsing the catalog is a prerequisite for the core
     * POS ordering flow, and the seeded cashier role has no 'products.*'
     * permission at all — gating this behind one would break the exact
     * workflow this endpoint exists to support.
     */
    public function index(Request $request)
    {
        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchId = $request->query('branch_id');

        if ($branchId !== null) {
            // A user may only request a branch they're actually assigned
            // to, unless they hold 'branches.view-all' (admins) — same
            // authorization convention as the BranchScoped trait uses.
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        } else {
            // No branch specified — default to the user's primary branch
            // (falls back to their first assigned branch if none is
            // marked primary). This is the "current branch/context" the
            // task asked for; there is no session-level "current branch"
            // concept anywhere else in the app yet to draw from.
            $branch = $user->branches()->wherePivot('is_primary', true)->first()
                ?? $user->branches()->first();

            if (! $branch) {
                return response()->json([
                    'success' => false,
                    'message' => 'No branch is assigned to this user',
                ], 422);
            }

            $branchId = $branch->id;
        }

        $categories = Category::query()
            ->where('is_active', true)
            ->where(function ($query) use ($branchId) {
                $query->whereNull('branch_id')
                    ->orWhere('branch_id', $branchId);
            })
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get(['id', 'branch_id', 'name', 'sort_order']);

        return response()->json([
            'success' => true,
            'data' => $categories,
        ]);
    }
}
