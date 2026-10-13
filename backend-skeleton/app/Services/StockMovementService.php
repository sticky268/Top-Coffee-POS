<?php

namespace App\Services;

use App\Models\Ingredient;
use App\Models\StockMovement;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;

class StockMovementService
{
    /**
     * Record a stock movement and update the ingredient balance atomically.
     *
     * Quantity is signed:
     * positive = stock added
     * negative = stock deducted
     */
    public function record(
        Ingredient $ingredient,
        string $type,
        float $quantity,
        int $createdBy,
        ?string $reason = null,
        ?Model $reference = null,
        ?float $unitCost = null,
        bool $unknownCost = false,
    ): StockMovement {
        if (! in_array($type, [
            'purchase',
            'sale_deduction',
            'adjustment',
            'wastage',
        ], true)) {
            throw new InvalidArgumentException('Invalid stock movement type.');
        }

        if ($quantity == 0.0) {
            throw new InvalidArgumentException('Stock movement quantity cannot be zero.');
        }

        if (in_array($type, ['adjustment', 'wastage'], true) && blank($reason)) {
            throw new InvalidArgumentException(
                'A reason is required for adjustment and wastage movements.'
            );
        }

        return DB::transaction(function () use (
            $ingredient,
            $type,
            $quantity,
            $createdBy,
            $reason,
            $reference,
            $unitCost,
            $unknownCost,
        ) {
            $query = Ingredient::query();

            if (
$reference instanceof \App\Models\Order && ($quantity > 0 || $type === 'wastage')
            ) {
                $query->withTrashed();
            }

            $lockedIngredient = $query
                ->whereKey($ingredient->id)
                ->lockForUpdate()
                ->first();

            if (! $lockedIngredient) {
                throw new RuntimeException('Ingredient not found.');
            }

            $currentStock = (float) $lockedIngredient->current_stock;
            $newBalance = $currentStock + $quantity;

            if ($newBalance < 0) {
                throw new InvalidArgumentException(
                    'Stock cannot be reduced below zero.'
                );
            }

            $cost = $lockedIngredient->average_unit_cost;
            if ($quantity > 0 && $unknownCost) $cost = null;
            if ($quantity > 0 && $unitCost !== null) {
                // Unknown opening stock stays unknown until exhausted or costed.
                $cost = $currentStock == 0 ? $unitCost : ($cost === null ? null :
                    ($currentStock * (float) $cost + $quantity * $unitCost) / $newBalance);
            }
            $lockedIngredient->forceFill([
                'average_unit_cost' => $cost,
                'current_stock' => $newBalance,
            ])->save();

            return StockMovement::create([
                'ingredient_id' => $lockedIngredient->id,
                'branch_id' => $lockedIngredient->branch_id,
                'type' => $type,
                'quantity' => $quantity,
                'balance_after' => $newBalance,
                'reference_type' => $reference?->getMorphClass(),
                'reference_id' => $reference?->getKey(),
                'reason' => $reason,
                'created_by' => $createdBy,
                'unit_cost' => $unknownCost ? null : ($unitCost ?? $lockedIngredient->average_unit_cost),
            ]);
        });
    }
}