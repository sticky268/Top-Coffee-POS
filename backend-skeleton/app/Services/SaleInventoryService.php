<?php

namespace App\Services;

use App\Models\Order;
use App\Models\RecipeItem;

class SaleInventoryService
{
    public function __construct(
        private StockMovementService $stockMovementService,
    ) {
    }

    /**
     * Reverse the inventory deduction previously applied to a completed sale.
     *
     * This appends positive sale_deduction movements rather than deleting or
     * modifying the original negative sale movements.
     */
    public function reverseForOrder(Order $order, int $createdBy): void
    {
        $movementRows = \App\Models\StockMovement::query()
            ->selectRaw('ingredient_id, SUM(quantity) as net_quantity, SUM(quantity * unit_cost) as net_cost, SUM(CASE WHEN unit_cost IS NULL THEN 1 ELSE 0 END) as unknown_costs')
            ->where('reference_type', $order->getMorphClass())
            ->where('reference_id', $order->id)
            ->where('type', 'sale_deduction')
            ->groupBy('ingredient_id')
            ->get();

        foreach ($movementRows as $movementRow) {
            $netQuantity = (float) $movementRow->net_quantity;

            if ($netQuantity == 0.0) {
                continue;
            }

            $ingredient = \App\Models\Ingredient::withTrashed()
                ->whereKey($movementRow->ingredient_id)
                ->first();

            if (! $ingredient) {
                throw new \RuntimeException(
                    "Ingredient {$movementRow->ingredient_id} not found."
                );
            }

            $this->stockMovementService->record(
                $ingredient,
                'sale_deduction',
                -$netQuantity,
                $createdBy,
                "Sale reversal for Order #{$order->id}",
                $order,
                $movementRow->unknown_costs == 0 ? (float) $movementRow->net_cost / $netQuantity : null,
                $movementRow->unknown_costs > 0,
            );
        }
    }

    /**
     * Deduct inventory for all recipe ingredients used by a completed sale.
     *
     * This method must be called while the order completion is inside
     * the surrounding database transaction.
     */
    public function deductForOrder(Order $order, int $createdBy): void
    {
        $order->loadMissing(['items.variant', 'items.modifiers', 'items.product.category']);

        foreach ($order->items as $orderItem) {
            $modifierIds = $orderItem->modifiers->pluck('modifier_id');
            $recipeItems = RecipeItem::query()
                ->where('branch_id', $order->branch_id)
                ->where(function ($q) use ($orderItem, $modifierIds) {
                    $q->where(fn ($base) => $base->where('product_id', $orderItem->product_id)->whereNull('modifier_id'))
                        ->orWhere(fn ($extra) => $extra->whereNull('product_id')->whereIn('modifier_id', $modifierIds));
                })
                ->get();

            $cost = 0.0;
            $costKnown = $recipeItems->isNotEmpty();
            foreach ($recipeItems as $recipeItem) {
                $quantity = (float) $recipeItem->quantity_used
                    * (int) $orderItem->quantity
                    * ($recipeItem->modifier_id === null ? (float) ($orderItem->variant?->recipe_multiplier ?? 1) : 1);
                $quantity = round($quantity, 3);

                abort_if($quantity <= 0, 422, 'Recipe consumption is below stock precision. Use a smaller ingredient unit.');

                $ingredient = $recipeItem->ingredient()->first();

                if (! $ingredient) {
                    throw new \RuntimeException(
                        "Ingredient {$recipeItem->ingredient_id} not found."
                    );
                }

                $movement = $this->stockMovementService->record(
                    $ingredient,
                    'sale_deduction',
                    -$quantity,
                    $createdBy,
                    "Sale deduction for Order #{$order->id}",
                    $order,
                );
                $costKnown = $costKnown && $movement->unit_cost !== null;
                $cost += $quantity * (float) $movement->unit_cost;
            }
            $orderItem->forceFill(['ingredient_cost' => $costKnown ? $cost : null,
                'sale_category_id' => $orderItem->product?->category_id,
                'sale_category_name' => $orderItem->product?->category?->name,
                'sale_category_captured' => true])->save();
        }
    }
}