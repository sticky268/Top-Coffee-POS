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
        $order->loadMissing('items');

        foreach ($order->items as $orderItem) {
            $recipeItems = RecipeItem::query()
                ->where('branch_id', $order->branch_id)
                ->where('product_id', $orderItem->product_id)
                ->whereNull('modifier_id')
                ->get();

            foreach ($recipeItems as $recipeItem) {
                $quantity = (float) $recipeItem->quantity_used
                    * (int) $orderItem->quantity;

                if ($quantity <= 0) {
                    continue;
                }

                $ingredient = $recipeItem->ingredient()->first();

                if (! $ingredient) {
                    throw new \RuntimeException(
                        "Ingredient {$recipeItem->ingredient_id} not found."
                    );
                }

                $this->stockMovementService->record(
                    $ingredient,
                    'sale_deduction',
                    $quantity,
                    $createdBy,
                    "Sale reversal for Order #{$order->id}",
                    $order,
                );
            }
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
        $order->loadMissing('items');

        foreach ($order->items as $orderItem) {
            $recipeItems = RecipeItem::query()
                ->where('branch_id', $order->branch_id)
                ->where('product_id', $orderItem->product_id)
                ->whereNull('modifier_id')
                ->get();

            foreach ($recipeItems as $recipeItem) {
                $quantity = (float) $recipeItem->quantity_used
                    * (int) $orderItem->quantity;

                if ($quantity <= 0) {
                    continue;
                }

                $ingredient = $recipeItem->ingredient()->first();

                if (! $ingredient) {
                    throw new \RuntimeException(
                        "Ingredient {$recipeItem->ingredient_id} not found."
                    );
                }

                $this->stockMovementService->record(
                    $ingredient,
                    'sale_deduction',
                    -$quantity,
                    $createdBy,
                    "Sale deduction for Order #{$order->id}",
                    $order,
                );
            }
        }
    }
}