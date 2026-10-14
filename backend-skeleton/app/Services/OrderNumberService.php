<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\Order;

class OrderNumberService
{
    /**
     * Return the next staff-facing order number for a branch.
     *
     * Call this inside the same DB transaction that creates the order.
     * Locking the branch row serializes number allocation for concurrent
     * cashiers at that branch while allowing different branches to proceed
     * independently.
     */
    public function nextForBranch(int $branchId): int
    {
        Branch::query()
            ->whereKey($branchId)
            ->lockForUpdate()
            ->firstOrFail();

        $currentMax = Order::withoutGlobalScopes()
            ->where('branch_id', $branchId)
            ->max('order_number');

        return ((int) $currentMax) + 1;
    }
}
