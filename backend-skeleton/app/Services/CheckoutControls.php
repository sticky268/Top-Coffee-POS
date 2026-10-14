<?php

namespace App\Services;

use App\Models\Order;
use App\Models\User;

class CheckoutControls
{
    public function manager(User $actor): bool
    {
        return $actor->hasAnyRole(['admin', 'manager']);
    }

    public function discount(Order $order): void
    {
        $actor = auth()->user();
        if (! $actor || ! $actor->business->require_manager_controls) return;
        $discount = OperationService::cents($order->discount_total);
        $subtotal = OperationService::cents($order->subtotal);
        abort_if($discount > $subtotal, 422, 'Discount cannot exceed the subtotal.');
        if ($discount <= 0) return;
        $large = $subtotal > 0 && $discount * 100 > $subtotal * (float) $actor->business->manager_discount_percent;
        abort_if($large && ! $this->manager($actor), 403, 'A manager must sign in to approve this discount.');
        if ($large) app(AuditLogService::class)->record(request(), 'order.discount_approved', $order, null, [
            'approved_by' => $actor->id, 'discount_total' => (float) $order->discount_total,
            'subtotal' => (float) $order->subtotal,
        ]);
    }
}
