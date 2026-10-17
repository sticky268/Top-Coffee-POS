<?php

namespace App\Services;

use App\Http\Middleware\RequireManagerPin;
use App\Models\{Branch, User};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Route, Schema};

class ManagerPinReadiness
{
    public function checks(array $businessIds): array
    {
        $schema = Schema::hasColumns('users', ['manager_pin_hash', 'manager_pin_failures', 'manager_pin_locked_until']);
        $routes = true;
        foreach (['refund' => 'refund', 'cancel' => 'void'] as $path => $action) {
            $route = Route::getRoutes()->match(Request::create('/api/v1/orders/1/'.$path, 'POST'));
            $routes = $routes && in_array(RequireManagerPin::class.':'.$action, $route->gatherMiddleware(), true);
        }
        $coverage = $schema && count($businessIds) > 0;
        foreach ($businessIds as $business) {
            $branches = Branch::where('business_id', $business)->where('is_active', true)->get();
            $managers = User::with(['roles', 'branches'])->where('business_id', $business)->where('is_active', true)->get()
                ->filter(fn ($user) => $user->hasAnyRole(['admin', 'manager']) && app(ManagerPin::class)->configured($user) && ! $user->manager_pin_locked_until?->isFuture()
                    && $user->can('orders.refund') && $user->can('orders.cancel'));
            $coverage = $coverage && $branches->isNotEmpty() && $branches->every(fn ($branch) =>
                $managers->contains(fn ($user) => $user->can('branches.view-all') || $user->branches->contains('id', $branch->id)));
        }
        return ['manager_pin_schema_available' => $schema,
            'manager_pin_enforced_for_void_and_refund' => $schema && $routes,
            'manager_pin_approver_for_every_active_branch' => $coverage];
    }
}
