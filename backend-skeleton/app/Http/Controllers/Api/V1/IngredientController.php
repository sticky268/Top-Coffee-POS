<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\RecipeItem;
use App\Models\StockMovement;
use App\Services\StockMovementService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class IngredientController extends Controller
{
    public function store(Request $request)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $user = $request->user();
        $branchId = $request->input('branch_id');

        if ($branchId !== null) {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to this branch.',
                ], 403);
            }
        } else {
            $branchId = $user->branches()->orderBy('branches.id')->value('branches.id');
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $validator = Validator::make(
            $request->all(),
            [
                'name' => ['required', 'string', 'max:255'],
                'unit_id' => ['required', 'integer', 'exists:units,id'],
                'reorder_threshold' => ['nullable', 'numeric', 'min:0'],
                'is_active' => ['nullable', 'boolean'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $ingredient = Ingredient::create([
            'branch_id' => $branchId,
            'unit_id' => $request->input('unit_id'),
            'name' => $request->input('name'),
            'reorder_threshold' => $request->input('reorder_threshold', 0),
            'is_active' => $request->boolean('is_active', true),
        ]);

        $ingredient->refresh();
        $ingredient->load('unit:id,name,abbreviation');

        return response()->json([
            'success' => true,
            'message' => 'Ingredient created successfully.',
            'data' => [
                'id' => $ingredient->id,
                'name' => $ingredient->name,
                'unit' => $ingredient->unit,
                'current_stock' => $ingredient->current_stock,
                'reorder_threshold' => $ingredient->reorder_threshold,
                'is_low_stock' => $ingredient->isLowStock(),
                'is_active' => $ingredient->is_active,
            ],
        ], 201);
    }

    public function update(Request $request, $id)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $ingredient = Ingredient::query()
            ->whereKey($id)
            ->first();

        if (! $ingredient) {
            return response()->json([
                'success' => false,
                'message' => 'Ingredient not found.',
            ], 404);
        }

        $validator = Validator::make(
            $request->all(),
            [
                'name' => ['required', 'string', 'max:255'],
                'unit_id' => ['required', 'integer', 'exists:units,id'],
                'reorder_threshold' => ['nullable', 'numeric', 'min:0'],
                'is_active' => ['nullable', 'boolean'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $newUnitId = (int) $request->input('unit_id');

        if ($newUnitId !== (int) $ingredient->unit_id) {
            $hasMovements = $ingredient->movements()->exists();

            $hasRecipeItems = RecipeItem::query()
                ->where('ingredient_id', $ingredient->id)
                ->exists();

            if ($hasMovements || $hasRecipeItems) {
                return response()->json([
                    'success' => false,
                    'message' => 'The ingredient unit cannot be changed after it has been used in stock movements or recipes.',
                ], 422);
            }
        }

        $ingredient->update([
            'unit_id' => $newUnitId,
            'name' => $request->input('name'),
            'reorder_threshold' => $request->input('reorder_threshold', 0),
            'is_active' => $request->boolean('is_active', true),
        ]);

        $ingredient->refresh();
        $ingredient->load('unit:id,name,abbreviation');

        return response()->json([
            'success' => true,
            'message' => 'Ingredient updated successfully.',
            'data' => [
                'id' => $ingredient->id,
                'name' => $ingredient->name,
                'unit' => $ingredient->unit,
                'current_stock' => $ingredient->current_stock,
                'reorder_threshold' => $ingredient->reorder_threshold,
                'is_low_stock' => $ingredient->isLowStock(),
                'is_active' => $ingredient->is_active,
            ],
        ]);
    }

    public function destroy(Request $request, $id)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $ingredient = Ingredient::query()
            ->whereKey($id)
            ->first();

        if (! $ingredient) {
            return response()->json([
                'success' => false,
                'message' => 'Ingredient not found.',
            ], 404);
        }

        $hasRecipeItems = RecipeItem::query()
            ->where('ingredient_id', $ingredient->id)
            ->exists();

        if ($hasRecipeItems) {
            return response()->json([
                'success' => false,
                'message' => 'This ingredient cannot be deleted because it is used in a recipe. Remove it from the recipe first.',
            ], 422);
        }

        $ingredient->delete();

        return response()->json([
            'success' => true,
            'message' => 'Ingredient deleted successfully.',
        ]);
    }

    public function movements(Request $request, $id)
    {
        if (! $request->user()->can('inventory.view')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $ingredient = Ingredient::query()
            ->with('unit:id,name,abbreviation')
            ->whereKey($id)
            ->first();

        if (! $ingredient) {
            return response()->json([
                'success' => false,
                'message' => 'Ingredient not found.',
            ], 404);
        }

        $validator = Validator::make(
            $request->all(),
            [
                'type' => ['nullable', 'string', 'in:purchase,adjustment,wastage,sale_deduction'],
                'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
                'page' => ['nullable', 'integer', 'min:1'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $perPage = (int) $request->input('per_page', 20);

        $movements = StockMovement::query()
            ->with('ingredient:id,name,unit_id')
            ->where('ingredient_id', $ingredient->id)
            ->when($request->filled('type'), function ($query) use ($request) {
                $query->where('type', $request->input('type'));
            })
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $movements->items(),
            'ingredient' => [
                'id' => $ingredient->id,
                'name' => $ingredient->name,
                'unit' => $ingredient->unit,
                'current_stock' => $ingredient->current_stock,
                'reorder_threshold' => $ingredient->reorder_threshold,
                'is_low_stock' => $ingredient->isLowStock(),
                'is_active' => $ingredient->is_active,
            ],
            'meta' => [
                'current_page' => $movements->currentPage(),
                'last_page' => $movements->lastPage(),
                'per_page' => $movements->perPage(),
                'total' => $movements->total(),
            ],
        ]);
    }

    public function recordMovement(Request $request, $id)
    {
        if (! $request->user()->can('inventory.adjust')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $validator = Validator::make(
            $request->all(),
            [
                'type' => ['required', 'string', 'in:purchase,adjustment,wastage,sale_deduction'],
                'quantity' => ['required', 'numeric', 'not_in:0'],
                'reason' => ['nullable', 'string', 'max:255'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $ingredient = Ingredient::query()
            ->whereKey($id)
            ->first();

        if (! $ingredient) {
            return response()->json([
                'success' => false,
                'message' => 'Ingredient not found.',
            ], 404);
        }

        $type = $request->input('type');
        $quantity = (float) $request->input('quantity');
        $reason = $request->input('reason');

        if (in_array($type, ['wastage', 'sale_deduction'], true) && $quantity > 0) {
            $quantity = -$quantity;
        }

        if ($type === 'purchase' && $quantity < 0) {
            return response()->json([
                'success' => false,
                'message' => 'Purchase quantity must be positive.',
            ], 422);
        }

        if (in_array($type, ['adjustment', 'wastage'], true) && blank($reason)) {
            return response()->json([
                'success' => false,
                'message' => 'A reason is required for adjustment and wastage movements.',
            ], 422);
        }

        try {
            $movement = app(StockMovementService::class)->record(
                $ingredient,
                $type,
                $quantity,
                $request->user()->id,
                $reason,
            );
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        } catch (\RuntimeException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 404);
        }

        $ingredient->refresh();
        $ingredient->refresh();
        $ingredient->load('unit:id,name,abbreviation');

        return response()->json([
            'success' => true,
            'message' => 'Stock movement recorded successfully.',
            'data' => [
                'movement' => $movement,
                'ingredient' => [
                    'id' => $ingredient->id,
                    'name' => $ingredient->name,
                    'unit' => $ingredient->unit,
                    'current_stock' => $ingredient->current_stock,
                    'reorder_threshold' => $ingredient->reorder_threshold,
                    'is_low_stock' => $ingredient->isLowStock(),
                    'is_active' => $ingredient->is_active,
                ],
            ],
        ], 201);
    }

    public function index(Request $request)
    {
        if (! $request->user()->can('inventory.view')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $user = $request->user();
        $branchId = $request->input('branch_id');

        if ($branchId !== null) {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to this branch.',
                ], 403);
            }
        } else {
            $branchId = $user->branches()->orderBy('branches.id')->value('branches.id');
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $ingredients = Ingredient::query()
            ->with('unit:id,name,abbreviation')
            ->where('branch_id', $branchId)
            ->orderBy('name')
            ->get();

        $data = $ingredients->map(function (Ingredient $ingredient) {
            return [
                'id' => $ingredient->id,
                'name' => $ingredient->name,
                'unit' => $ingredient->unit,
                'current_stock' => $ingredient->current_stock,
                'reorder_threshold' => $ingredient->reorder_threshold,
                'is_low_stock' => $ingredient->isLowStock(),
                'is_active' => $ingredient->is_active,
            ];
        });

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }
}
