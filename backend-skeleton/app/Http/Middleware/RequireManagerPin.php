<?php

namespace App\Http\Middleware;

use App\Models\Order;
use App\Services\ManagerPin;
use Closure;
use Illuminate\Http\Request;

class RequireManagerPin
{
    public function handle(Request $request, Closure $next, string $action)
    {
        $permission = match ($action) { 'refund' => 'orders.refund', 'void' => 'orders.cancel' };
        $user = $request->user();
        abort_unless($user->can($permission), 403, 'You do not have permission for this action.');
        abort_if($request->filled('expected_user_id') && $request->integer('expected_user_id') !== $user->id, 403, 'Session changed.');
        // Scope the target before checking credentials; a foreign order cannot
        // consume another branch's PIN attempts or reveal enrollment state.
        $order = Order::whereKey($request->route('id'))
            ->whereHas('branch', fn ($query) => $query->where('business_id', $user->business_id))->firstOrFail();
        abort_unless($user->can('branches.view-all') || $user->branches()->where('branches.id', $order->branch_id)->exists(), 403, 'Branch access denied.');
        if ($action === 'refund') abort_unless($request->integer('branch_id') === (int) $order->branch_id, 404, 'Order not found.');
        app(ManagerPin::class)->verify($request, $order, $action);
        return $next($request);
    }
}
