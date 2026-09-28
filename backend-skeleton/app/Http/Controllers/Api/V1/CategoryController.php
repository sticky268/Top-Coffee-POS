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
     * specific to that branch.
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
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        } else {
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

    /**
     * POST /api/v1/categories
     *
     * Creates a category for the selected branch.
     *
     * Requires products.manage, matching ProductController::store().
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage categories',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'branch_id' => 'required|integer|exists:branches,id',
            'name' => 'required|string|max:255',
            'sort_order' => 'nullable|integer|min:0',
            'is_active' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchId = (int) $request->input('branch_id');

        if (
            ! $user->can('branches.view-all')
            && ! $user->branches()->where('branches.id', $branchId)->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => "You do not have access to branch {$branchId}",
            ], 403);
        }

        $category = Category::create([
            'branch_id' => $branchId,
            'name' => $request->input('name'),
            'sort_order' => $request->input('sort_order', 0),
            'is_active' => $request->boolean('is_active', true),
        ]);

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $category->id,
                'branch_id' => $category->branch_id,
                'name' => $category->name,
                'sort_order' => $category->sort_order,
            ],
        ], 201);
    }

    /**
     * PATCH /api/v1/categories/{category}
     *
     * Updates a category belonging to an accessible branch.
     * Global categories (branch_id IS NULL) cannot be modified here.
     */
    public function update(Request $request, Category $category)
    {
        if (! $request->user()->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage categories',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'sort_order' => 'sometimes|required|integer|min:0',
            'is_active' => 'sometimes|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();

        if ($category->branch_id === null) {
            return response()->json([
                'success' => false,
                'message' => 'Global categories cannot be modified',
            ], 403);
        }

        if (
            ! $user->can('branches.view-all')
            && ! $user->branches()->where('branches.id', $category->branch_id)->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => "You do not have access to branch {$category->branch_id}",
            ], 403);
        }

        $category->fill($request->only([
            'name',
            'sort_order',
        ]));

        if ($request->has('is_active')) {
            $category->is_active = $request->boolean('is_active');
        }

        $category->save();

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $category->id,
                'branch_id' => $category->branch_id,
                'name' => $category->name,
                'sort_order' => $category->sort_order,
                'is_active' => (bool) $category->is_active,
            ],
        ]);
    }

    /**
     * DELETE /api/v1/categories/{category}
     *
     * Deactivates the category instead of physically deleting it.
     * This is required because products may reference the category.
     */
    public function destroy(Request $request, Category $category)
    {
        if (! $request->user()->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage categories',
            ], 403);
        }

        $user = $request->user();

        if ($category->branch_id === null) {
            return response()->json([
                'success' => false,
                'message' => 'Global categories cannot be deactivated',
            ], 403);
        }

        if (
            ! $user->can('branches.view-all')
            && ! $user->branches()->where('branches.id', $category->branch_id)->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => "You do not have access to branch {$category->branch_id}",
            ], 403);
        }

        $category->is_active = false;
        $category->save();

        return response()->json([
            'success' => true,
            'message' => 'Category deactivated successfully',
        ]);
    }
}