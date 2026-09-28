<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Payment;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Validator;

class ReportsController extends Controller
{
    /**
     * GET /api/v1/reports
     *
     * Returns sales report data for a selected date range.
     */
    public function index(Request $request)
    {
        if (! $request->user()->can('reports.view')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view reports',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date|after_or_equal:date_from',
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

        $dateFrom = $request->query('date_from')
            ? Carbon::parse($request->query('date_from'))->startOfDay()
            : Carbon::today()->startOfDay();

        $dateTo = $request->query('date_to')
            ? Carbon::parse($request->query('date_to'))->endOfDay()
            : Carbon::today()->endOfDay();

        $orders = Order::query()
            ->where('status', 'completed')
            ->whereBetween('created_at', [$dateFrom, $dateTo])
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            });

        $totalSales = (float) (clone $orders)->sum('total');
        $totalOrders = (int) (clone $orders)->count();

        $averageOrderValue = $totalOrders > 0
            ? round($totalSales / $totalOrders, 2)
            : 0;

        $salesOverview = collect();
        $currentDate = $dateFrom->copy()->startOfDay();

        while ($currentDate->lte($dateTo)) {
            $nextDate = $currentDate->copy()->addDay();

            $dailySales = (float) (clone $orders)
                ->where('created_at', '>=', $currentDate)
                ->where('created_at', '<', $nextDate)
                ->sum('total');

            $salesOverview->push([
                'date' => $currentDate->toDateString(),
                'total' => $dailySales,
            ]);

            $currentDate->addDay();
        }

        $hourlySales = collect();

        if ($dateFrom->toDateString() === $dateTo->toDateString()) {
            $currentHour = $dateFrom->copy()->startOfHour();

            for ($hour = 0; $hour < 24; $hour++) {
                $nextHour = $currentHour->copy()->addHour();

                $hourlyTotal = (float) (clone $orders)
                    ->where('created_at', '>=', $currentHour)
                    ->where('created_at', '<', $nextHour)
                    ->sum('total');

                $hourlySales->push([
                    'hour' => $currentHour->format('H:00'),
                    'total' => $hourlyTotal,
                ]);

                $currentHour->addHour();
            }
        }

        $orderTypes = (clone $orders)
            ->selectRaw('order_type, COUNT(*) as count, SUM(total) as total')
            ->groupBy('order_type')
            ->orderBy('order_type')
            ->get()
            ->map(function ($orderType) {
                return [
                    'type' => $orderType->order_type,
                    'count' => (int) $orderType->count,
                    'total' => (float) $orderType->total,
                ];
            })
            ->values();

        $topProducts = \App\Models\OrderItem::query()
            ->whereHas('order', function ($query) use ($dateFrom, $dateTo, $branchId) {
                $query->where('status', 'completed')
                    ->whereBetween('created_at', [$dateFrom, $dateTo])
                    ->when($branchId !== null, function ($query) use ($branchId) {
                        $query->where('branch_id', $branchId);
                    });
            })
            ->whereNotNull('product_id')
            ->join('products', 'order_items.product_id', '=', 'products.id')
            ->selectRaw('
                order_items.product_id,
                products.name as product_name,
                SUM(order_items.quantity) as quantity_sold,
                SUM(order_items.quantity * order_items.unit_price) as sales_total
            ')
            ->groupBy('order_items.product_id', 'products.name')
            ->orderByDesc('quantity_sold')
            ->orderBy('products.name')
            ->limit(10)
            ->get()
            ->map(function ($product) {
                return [
                    'product_id' => (int) $product->product_id,
                    'product_name' => $product->product_name,
                    'quantity_sold' => (int) $product->quantity_sold,
                    'sales_total' => (float) $product->sales_total,
                ];
            })
            ->values();

        $paymentMethods = Payment::query()
            ->whereHas('order', function ($query) use ($dateFrom, $dateTo, $branchId) {
                $query->where('status', 'completed')
                    ->whereBetween('created_at', [$dateFrom, $dateTo])
                    ->when($branchId !== null, function ($query) use ($branchId) {
                        $query->where('branch_id', $branchId);
                    });
            })
            ->selectRaw('method, SUM(amount) as total, COUNT(*) as count')
            ->groupBy('method')
            ->orderBy('method')
            ->get()
            ->map(function ($payment) {
                return [
                    'method' => $payment->method,
                    'total' => (float) $payment->total,
                    'count' => (int) $payment->count,
                ];
            })
            ->values();

        return response()->json([
            'success' => true,
            'data' => [
                'summary' => [
                    'date_from' => $dateFrom->toDateString(),
                    'date_to' => $dateTo->toDateString(),
                    'total_sales' => $totalSales,
                    'total_orders' => $totalOrders,
                    'average_order_value' => $averageOrderValue,
                ],
                'sales_overview' => $salesOverview,
                'hourly_sales' => $hourlySales,
                'payment_methods' => $paymentMethods,
                'order_types' => $orderTypes,
                'top_products' => $topProducts,
            ],
        ]);
    }
}