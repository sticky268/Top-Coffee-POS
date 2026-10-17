<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\CashierShift;
use App\Models\Product;
use App\Services\OperationService;
use App\Services\RecipeCostService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

class OperationsReportController extends Controller
{
    public function availability(Request $request, OperationService $ops, RecipeCostService $costs)
    {
        $branch = $ops->branch($request, 'inventory.view');
        $products = Product::where('is_active', true)->whereHas('branches', fn ($q) => $q->where('branches.id', $branch))->with('variants')->get();
        return ['success' => true, 'data' => $products->map(fn ($p) => $costs->preview($p, $branch) + ['variants' => $p->variants->where('is_active', true)->map(fn ($v) => $costs->preview($p, $branch, (float) $v->recipe_multiplier) + ['variant_id' => $v->id, 'variant_name' => $v->name])->values()])];
    }

    public function report(Request $request, OperationService $ops)
    {
        $branch = $ops->branch($request, 'reports.view');
        $request->validate(['date_from' => 'required|date_format:Y-m-d', 'date_to' => 'required|date_format:Y-m-d|after_or_equal:date_from']);
        $timezone = \App\Models\Branch::findOrFail($branch)->timezone ?: 'UTC';
        $start = Carbon::parse($request->input('date_from'), $timezone)->startOfDay()->utc();
        $end = Carbon::parse($request->input('date_to'), $timezone)->endOfDay()->utc();
        abort_if($start->diffInDays($end) > 366, 422, 'Choose at most one year.');
        $orders = Order::where('branch_id', $branch)->where('status', 'completed')->whereBetween('completed_at', [$start, $end]);
        $refunds = DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')->join('orders', 'orders.id', '=', 'payments.order_id')->where('orders.branch_id', $branch)->whereBetween('payment_refunds.created_at', [$start, $end])->sum('payment_refunds.amount');
        $items = DB::table('order_items')->whereIn('order_id', (clone $orders)->select('id'));
        $unknown = (clone $items)->whereNull('ingredient_cost')->count();
        $cost = (float) (clone $items)->whereNotNull('ingredient_cost')->sum('ingredient_cost');
        $gross = (float) DB::table('payments')->join('orders', 'orders.id', '=', 'payments.order_id')
            ->where('orders.branch_id', $branch)->whereIn('payments.status', ['completed', 'partially_refunded', 'refunded'])
            ->whereBetween('payments.created_at', [$start, $end])->sum('payments.amount');
        // Use movement-time cost snapshots: a restock reverses consumption in
        // its own reporting period, while a wastage reclassification is separate.
        $consumption = DB::table('stock_movements')->where('branch_id', $branch)
            ->where('type', 'sale_deduction')->whereBetween('created_at', [$start, $end]);
        $cost = -(float) (clone $consumption)->selectRaw('SUM(quantity * unit_cost) as value')->value('value');
        $unknownMovements = (clone $consumption)->whereNull('unit_cost')->count();
        $waste = DB::table('stock_movements')->where('branch_id', $branch)->where('type', 'wastage')->whereBetween('created_at', [$start, $end]);
        // An aggregate can hide two offsetting drawer discrepancies. Return
        // bounded, branch-scoped source records for a manager to inspect.
        $cashDifferences = CashierShift::where('branch_id', $branch)->where('status', 'closed')
            ->where('difference', '!=', 0)->whereBetween('closed_at', [$start, $end]);
        $cashDifferenceCount = (clone $cashDifferences)->count();
        $cashDifferenceRows = (clone $cashDifferences)->orderByDesc('closed_at')->orderByDesc('id')
            ->limit(20)->get(['id', 'difference', 'closed_at', 'reviewed_at']);
        // Stock count adjustments are already in the immutable movement ledger.
        // This is a read-only review; it does not claim manager approval.
        $stockDifferences = DB::table('stock_movements as movements')
            ->join('ingredients', 'ingredients.id', '=', 'movements.ingredient_id')
            ->join('units', 'units.id', '=', 'ingredients.unit_id')
            ->whereColumn('ingredients.branch_id', 'movements.branch_id')
            ->where('movements.branch_id', $branch)->where('movements.type', 'adjustment')
            ->where('movements.reason', 'like', 'Stock count: %')
            ->where('movements.quantity', '!=', 0)
            ->whereBetween('movements.created_at', [$start, $end]);
        $stockDifferenceCount = (clone $stockDifferences)->count();
        $stockDifferenceRows = (clone $stockDifferences)->orderByDesc('movements.created_at')
            ->orderByDesc('movements.id')->limit(20)
            ->get(['movements.id', 'movements.ingredient_id', 'ingredients.name as ingredient_name',
                'ingredients.current_stock', 'ingredients.reorder_threshold', 'ingredients.is_active',
                'units.id as unit_id', 'units.name as unit_name', 'units.abbreviation as unit_abbreviation',
                'movements.quantity', 'movements.balance_after', 'movements.reason', 'movements.created_at']);
        return ['success' => true, 'data' => [
            'gross_sales' => $gross, 'refunds' => (float) $refunds, 'net_sales' => round($gross - $refunds, 2),
            'discounts' => (float) (clone $orders)->sum('discount_total'), 'orders' => (clone $orders)->count(),
            'known_ingredient_cost' => round($cost, 2), 'unknown_cost_items' => $unknown,
            'ingredient_margin' => $unknown === 0 && $unknownMovements === 0 ? round($gross - $refunds - $cost, 2) : null,
            'unknown_cost_movements' => $unknownMovements,
            'wastage_cost' => round(abs((float) (clone $waste)->selectRaw('SUM(quantity * unit_cost) as value')->value('value')), 2),
            'unpriced_wastage_movements' => (clone $waste)->whereNull('unit_cost')->count(),
            'cash_difference' => (float) CashierShift::where('branch_id', $branch)->whereBetween('closed_at', [$start, $end])->sum('difference'),
            'cash_difference_shift_count' => $cashDifferenceCount,
            'cash_difference_shifts' => $cashDifferenceRows,
            'stock_count_discrepancy_count' => $stockDifferenceCount,
            'stock_count_discrepancies' => $stockDifferenceRows,
            'unassigned_cash_payments' => DB::table('payments')->join('orders', 'orders.id', '=', 'payments.order_id')->where('orders.branch_id', $branch)->where('payments.method', 'cash')->whereNull('payments.shift_id')->whereBetween('payments.created_at', [$start, $end])->count(),
            'unreviewed_shifts' => CashierShift::where('branch_id', $branch)->where('status', 'closed')->whereNull('reviewed_at')->count(),
        ]];
    }
}
