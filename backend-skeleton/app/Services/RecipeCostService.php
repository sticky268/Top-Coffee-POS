<?php

namespace App\Services;

use App\Models\RecipeItem;
use App\Models\Product;

class RecipeCostService
{
    public function preview(Product $product, int $branch, float $multiplier = 1): array
    {
        $items = RecipeItem::where('branch_id', $branch)->where('product_id', $product->id)->whereNull('modifier_id')->with('ingredient')->get();
        $cost = 0;
        $known = $items->isNotEmpty();
        $available = null;
        foreach ($items as $item) {
            $ingredient = $item->ingredient;
            $used = (float) $item->quantity_used * $multiplier;
            if (! $ingredient || ! $ingredient->is_active || $used <= 0) { $known = false; $available = 0; continue; }
            $available = min($available ?? PHP_INT_MAX, (int) floor((float) $ingredient->current_stock / $used));
            if ($ingredient->average_unit_cost === null) $known = false;
            $cost += $used * (float) $ingredient->average_unit_cost;
        }
        return ['product_id' => $product->id, 'name' => $product->name, 'recipe_multiplier' => $multiplier, 'ingredient_cost' => $known ? round($cost, 4) : null, 'available_servings' => $available, 'cost_complete' => $known];
    }
}
