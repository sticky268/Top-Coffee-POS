<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\Product;
use App\Models\RecipeItem;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class RecipeController extends Controller
{
    public function show(Request $request, Product $product)
    {
        $user = $request->user();
        $branchId = $this->resolveBranchId($request);

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        if (! $this->canAccessBranch($user, $branchId)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch.',
            ], 403);
        }

        $items = RecipeItem::query()
            ->where('branch_id', $branchId)
            ->where('product_id', $product->id)
            ->whereNull('modifier_id')
            ->with('ingredient.unit')
            ->orderBy('id')
            ->get();

        return response()->json([
            'success' => true,
            'data' => [
                'product' => [
                    'id' => $product->id,
                    'name' => $product->name,
                ],
                'branch_id' => $branchId,
                'items' => $items->map(function (RecipeItem $item) {
                    return [
                        'id' => $item->id,
                        'ingredient_id' => $item->ingredient_id,
                        'ingredient' => [
                            'id' => $item->ingredient->id,
                            'name' => $item->ingredient->name,
                            'unit_id' => $item->ingredient->unit_id,
                            'unit' => [
                                'id' => $item->ingredient->unit->id,
                                'name' => $item->ingredient->unit->name,
                                'abbreviation' => $item->ingredient->unit->abbreviation,
                            ],
                        ],
                        'quantity_used' => $item->quantity_used,
                    ];
                })->values(),
            ],
        ]);
    }

    public function update(Request $request, Product $product)
    {
        $user = $request->user();

        if (! $user->can('products.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage products',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'branch_id' => ['nullable', 'integer', 'exists:branches,id'],
            'items' => ['required', 'array'],
            'items.*.ingredient_id' => ['required', 'integer', 'distinct'],
            'items.*.quantity_used' => ['required', 'numeric', 'gt:0'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        if (! $this->canAccessBranch($user, $branchId)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch.',
            ], 403);
        }

        $ingredientIds = collect($request->input('items'))
            ->pluck('ingredient_id')
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->values();

        $validIngredientIds = Ingredient::query()
            ->where('branch_id', $branchId)
            ->whereIn('id', $ingredientIds)
            ->pluck('id');

        $invalidIngredientIds = $ingredientIds
            ->diff($validIngredientIds)
            ->values();

        if ($invalidIngredientIds->isNotEmpty()) {
            return response()->json([
                'success' => false,
                'message' => 'One or more ingredients do not belong to the selected branch.',
                'invalid_ingredient_ids' => $invalidIngredientIds,
            ], 422);
        }

        $recipeItems = DB::transaction(function () use (
            $branchId,
            $product,
            $request
        ) {
            RecipeItem::query()
                ->where('branch_id', $branchId)
                ->where('product_id', $product->id)
                ->whereNull('modifier_id')
                ->delete();

            foreach ($request->input('items') as $item) {
                RecipeItem::create([
                    'branch_id' => $branchId,
                    'product_id' => $product->id,
                    'modifier_id' => null,
                    'ingredient_id' => (int) $item['ingredient_id'],
                    'quantity_used' => $item['quantity_used'],
                ]);
            }

            return RecipeItem::query()
                ->where('branch_id', $branchId)
                ->where('product_id', $product->id)
                ->whereNull('modifier_id')
                ->with('ingredient.unit')
                ->orderBy('id')
                ->get();
        });

        return response()->json([
            'success' => true,
            'message' => 'Recipe updated successfully.',
            'data' => [
                'product' => [
                    'id' => $product->id,
                    'name' => $product->name,
                ],
                'branch_id' => $branchId,
                'items' => $recipeItems->map(function (RecipeItem $item) {
                    return [
                        'id' => $item->id,
                        'ingredient_id' => $item->ingredient_id,
                        'ingredient' => [
                            'id' => $item->ingredient->id,
                            'name' => $item->ingredient->name,
                            'unit_id' => $item->ingredient->unit_id,
                            'unit' => [
                                'id' => $item->ingredient->unit->id,
                                'name' => $item->ingredient->unit->name,
                                'abbreviation' => $item->ingredient->unit->abbreviation,
                            ],
                        ],
                        'quantity_used' => $item->quantity_used,
                    ];
                })->values(),
            ],
        ]);
    }

    private function resolveBranchId(Request $request): ?int
    {
        if ($request->filled('branch_id')) {
            return (int) $request->input('branch_id');
        }

        return $request->user()
            ->branches()
            ->orderBy('branches.id')
            ->value('branches.id');
    }

    private function canAccessBranch($user, int $branchId): bool
    {
        return $user->can('branches.view-all')
            || $user->branches()
                ->where('branches.id', $branchId)
                ->exists();
    }
}