<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Payment;
use App\Models\Branch;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\DB;

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

        // Selected-branch dates are business-local; cross-branch reports use UTC.
        $timezone = $branchId === null ? 'UTC'
            : (Branch::withTrashed()->findOrFail($branchId)->timezone ?: 'UTC');
        $dateFrom = $request->query('date_from')
            ? Carbon::parse($request->query('date_from'), $timezone)->startOfDay()
            : Carbon::today($timezone);
        $dateTo = $request->query('date_to')
            ? Carbon::parse($request->query('date_to'), $timezone)->endOfDay()
            : Carbon::today($timezone)->endOfDay();
        abort_if($dateTo->lt($dateFrom) || $dateFrom->diffInDays($dateTo) >= 366,
            422, 'Choose an ordered date range of at most 366 days.');

        $orders = Order::query()
            ->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'))
            ->where('status', 'completed')
            ->completedDuring($dateFrom->copy()->utc(), $dateTo->copy()->addMicrosecond()->utc())
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            });

        $totalSales = (float) (clone $orders)->sum('total');
        $totalOrders = (int) (clone $orders)->count();
        $supplementalSales = (float) (clone $orders)->sum('supplemental_total');
        $refunds = (float) DB::table('payment_refunds')
            ->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')
            ->whereIn('payments.order_id', (clone $orders)->select('orders.id'))
            ->sum('payment_refunds.amount');

        $averageOrderValue = $totalOrders > 0
            ? round($totalSales / $totalOrders, 2)
            : 0;

        $days = [];
        for ($day = $dateFrom->copy(); $day->lte($dateTo); $day->addDay()) {
            $days[] = [$day->copy(), $day->copy()->addDay(), $day->toDateString()];
        }
        $dailyTotals = $this->bucketTotals($orders, $days);
        $salesOverview = collect($days)->map(fn ($bucket, $i) => [
            'date' => $bucket[2], 'total' => $dailyTotals[$i],
        ]);

        $hours = [];
        if ($dateFrom->toDateString() === $dateTo->toDateString()) {
            // Advance real UTC hours so DST transitions produce 23 or 25 buckets.
            for ($hour = $dateFrom->copy()->utc(); $hour->lte($dateTo->copy()->utc()); $hour->addHour()) {
                $local = $hour->copy()->setTimezone($timezone);
                $hours[] = [$hour->copy(), $hour->copy()->addHour(), $local->format('H:00')];
            }
        }
        $labels = array_count_values(array_column($hours, 2));
        foreach ($hours as &$bucket) {
            if ($labels[$bucket[2]] > 1) {
                $bucket[2] .= ' '.$bucket[0]->copy()->setTimezone($timezone)->format('P');
            }
        }
        unset($bucket);
        $hourlyTotals = $this->bucketTotals($orders, $hours);
        $hourlySales = collect($hours)->map(fn ($bucket, $i) => [
            'hour' => $bucket[2], 'total' => $hourlyTotals[$i],
        ]);

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
            ->whereHas('order', function ($query) use ($dateFrom, $dateTo, $branchId, $businessId) {
                $query->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'));
                $query->where('status', 'completed')
                    ->completedDuring($dateFrom->copy()->utc(), $dateTo->copy()->addMicrosecond()->utc())
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
            ->where(function ($query) {
                $query->where('status', 'completed')
                    ->orWhere(fn ($query) => $query->whereIn('status', ['partially_refunded', 'refunded'])->whereHas('refunds'));
            })
            ->whereHas('order', function ($query) use ($dateFrom, $dateTo, $branchId, $businessId) {
                $query->whereIn('orders.branch_id', Branch::withTrashed()->where('business_id', $businessId)->select('id'));
                $query->where('status', 'completed')
                    ->completedDuring($dateFrom->copy()->utc(), $dateTo->copy()->addMicrosecond()->utc())
                    ->when($branchId !== null, function ($query) use ($branchId) {
                        $query->where('branch_id', $branchId);
                    });
            })
            ->selectRaw('method, SUM(amount - COALESCE((SELECT SUM(payment_refunds.amount) FROM payment_refunds WHERE payment_refunds.payment_id = payments.id), 0)) as total, COUNT(*) as count')
            ->groupBy('method')
            ->havingRaw('SUM(amount - COALESCE((SELECT SUM(payment_refunds.amount) FROM payment_refunds WHERE payment_refunds.payment_id = payments.id), 0)) > 0')
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
                    'timezone' => $timezone,
                    'date_basis' => 'completion',
                    'date_to' => $dateTo->toDateString(),
                    'total_sales' => $totalSales,
                    'supplemental_sales' => $supplementalSales,
                    'refunds' => $refunds,
                    'net_sales' => round($totalSales + $supplementalSales - $refunds, 2),
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
    /** One aggregate query per chart, independent of the number of buckets. */
    private function bucketTotals($orders, array $buckets): array
    {
        if ($buckets === []) return [];
        $selects = [];
        $bindings = [];
        foreach ($buckets as $i => [$from, $to]) {
            $selects[] = "COALESCE(SUM(CASE WHEN COALESCE(orders.completed_at, orders.created_at) >= ? AND COALESCE(orders.completed_at, orders.created_at) < ? THEN total ELSE 0 END), 0) AS bucket_$i";
            $bindings[] = $from->copy()->utc()->toDateTimeString();
            $bindings[] = $to->copy()->utc()->toDateTimeString();
        }
        $row = (clone $orders)->selectRaw(implode(', ', $selects), $bindings)->first();
        return array_map(fn ($i) => (float) ($row->{"bucket_$i"} ?? 0), array_keys($buckets));
    }

}
