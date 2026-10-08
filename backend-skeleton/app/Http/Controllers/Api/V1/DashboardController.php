<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\Order;
use App\Models\Branch;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Validator;

class DashboardController extends Controller
{
    /**
     * GET /api/v1/dashboard
     *
     * Returns the data needed by the POS dashboard.
     */
    public function index(Request $request)
    {
        if (! $request->user()->can('orders.view')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view the dashboard',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchId = $request->query('branch_id');
        $businessId = $user->business_id;

        if ($branchId !== null && ! Branch::withTrashed()->where('business_id', $businessId)->whereKey($branchId)->exists()) {
            return response()->json(['success' => false, 'message' => 'You do not have access to that branch'], 403);
        }

        if ($branchId !== null && ! $user->can('branches.view-all')) {
            $hasAccess = $user->branches()
                ->where('branches.id', $branchId)
                ->exists();

            if (! $hasAccess) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        }

        $today = Carbon::today();
        $tomorrow = $today->copy()->addDay();

        $todayOrders = Order::query()
            ->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'))
            ->where('status', 'completed')
            ->where('created_at', '>=', $today)
            ->where('created_at', '<', $tomorrow)
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            });

        $todaysSales = (float) (clone $todayOrders)->sum('total');
        $todaysOrderCount = (int) (clone $todayOrders)->count();

        $averageOrderValue = $todaysOrderCount > 0
            ? round($todaysSales / $todaysOrderCount, 2)
            : 0;

        $lowStockItemCount = Ingredient::query()
            ->whereIn('branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'))
            ->where('is_active', true)
            ->whereColumn('current_stock', '<=', 'reorder_threshold')
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            })
            ->count();

        $recentOrders = Order::query()
            ->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'))
            ->with(['branch:id,name,code', 'cashier:id,name', 'payments'])
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            })
            ->orderByDesc('created_at')
            ->limit(5)
            ->get()
            ->map(function (Order $order) {
                $payments = $order->payments->where('status', 'completed');
                $paymentMethod = $payments->count() > 1 ? 'split' : $payments->first()?->method;

                return [
                    'id' => $order->id,
                    'order_number' => (string) ($order->order_number ?? $order->id),
                    'order_type' => $order->order_type,
                    'status' => $order->status,
                    'total' => (float) $order->total,
                    'item_count' => $order->items()->sum('quantity'),
                    'branch' => $order->branch ? [
                        'id' => $order->branch->id,
                        'name' => $order->branch->name,
                        'code' => $order->branch->code,
                    ] : null,
                    'cashier' => $order->cashier ? [
                        'id' => $order->cashier->id,
                        'name' => $order->cashier->name,
                    ] : null,
                    'payment_method' => $paymentMethod,
                    'created_at' => $order->created_at?->toIso8601String(),
                ];
            })
            ->values();

        $salesOverview = collect(range(6, 0))
            ->map(function (int $daysAgo) use ($branchId, $businessId) {
                $date = Carbon::today()->subDays($daysAgo);
                $nextDate = $date->copy()->addDay();

                $total = Order::query()
                    ->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'))
                    ->where('status', 'completed')
                    ->where('created_at', '>=', $date)
                    ->where('created_at', '<', $nextDate)
                    ->when($branchId !== null, function ($query) use ($branchId) {
                        $query->where('branch_id', $branchId);
                    })
                    ->sum('total');

                return [
                    'date' => $date->toDateString(),
                    'total' => (float) $total,
                ];
            })
            ->values();

        return response()->json([
            'success' => true,
            'data' => [
                'stats' => [
                    'todays_sales' => $todaysSales,
                    'todays_orders' => $todaysOrderCount,
                    'average_order_value' => $averageOrderValue,
                    'low_stock_item_count' => $lowStockItemCount,
                ],
                'recent_orders' => $recentOrders,
                'sales_overview' => $salesOverview,
            ],
        ]);
    }
}
