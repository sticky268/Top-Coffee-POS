<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\Product;
use App\Services\OperationService;
use Illuminate\Http\Request;

class IngredientImpactController extends Controller
{
    public function __invoke(Request $request, int $id, OperationService $operations)
    {
        $branch = $operations->branch($request, 'inventory.view');
        $request->validate(['after_id' => ['nullable', 'integer', 'min:0']]);
        $ingredient = Ingredient::query()
            ->where('branch_id', $branch)->whereKey($id)->firstOrFail();

        // Match the same base/optional-modifier recipe relationships used by
        // SaleInventoryService. These links do not estimate sale availability.
        $recipe = fn ($query) => $query
            ->where('recipe_items.branch_id', $branch)
            ->where('recipe_items.ingredient_id', $ingredient->id)
            ->where('quantity_used', '>', 0);
        $products = Product::query()
            ->where('is_active', true)
            ->whereHas('branches', fn ($query) => $query
                ->where('branches.id', $branch)
                ->where('branch_product.is_available', true))
            ->where(function ($query) use ($recipe) {
                $query->whereHas('recipeItems', fn ($items) =>
                    $recipe($items)->whereNull('modifier_id'))
                    ->orWhereHas('modifierGroups.modifiers', fn ($modifiers) =>
                        $modifiers->where('modifiers.is_active', true)
                            ->whereHas('recipeItems', fn ($items) =>
                                $recipe($items)->whereNull('product_id')));
            })
            ->when($request->filled('after_id'), fn ($query) =>
                $query->where('products.id', '>', $request->integer('after_id')))
            ->orderBy('products.id')
            ->limit(21)
            ->get(['products.id', 'products.name']);
        $hasMore = $products->count() > 20;
        $page = $products->take(20)->values();

        return response()->json([
            'success' => true,
            'branch_id' => $branch,
            'ingredient_id' => $ingredient->id,
            'data' => $page->map(fn ($product) => [
                'id' => $product->id, 'name' => $product->name,
            ]),
            'meta' => [
                'per_page' => 20,
                'next_after_id' => $hasMore ? $page->last()->id : null,
            ],
        ]);
    }
}
