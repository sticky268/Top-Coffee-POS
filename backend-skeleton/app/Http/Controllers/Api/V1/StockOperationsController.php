<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Services\OperationService;
use App\Services\StockMovementService;
use App\Services\UnitConversionService;
use App\Services\AuditLogService;
use Illuminate\Http\Request;

class StockOperationsController extends Controller
{
    public function count(Request $request, OperationService $ops)
    {
        $branch = $ops->branch($request, 'inventory.adjust');
        $request->validate(['ingredient_id' => 'required|integer', 'expected_stock' => 'required|numeric|min:0|decimal:0,3', 'counted_stock' => 'required|numeric|min:0|decimal:0,3', 'reason' => 'required|string|max:255', 'unit_cost' => 'nullable|numeric|min:0|max:9999999|decimal:0,6']);
        $result = $ops->run($request, $branch, 'stock.count', function () use ($request, $branch) {
            $ingredient = Ingredient::whereKey($request->integer('ingredient_id'))->where('branch_id', $branch)->lockForUpdate()->firstOrFail();
            abort_if(abs((float) $ingredient->current_stock - (float) $request->input('expected_stock')) > 0.0001, 409, 'Stock changed during counting. Refresh and reconcile the count.');
            if ($request->filled('unit_cost')) $ingredient->forceFill(['average_unit_cost' => $request->input('unit_cost')])->save();
            $delta = round((float) $request->input('counted_stock') - (float) $ingredient->current_stock, 3);
            if ($delta != 0) app(StockMovementService::class)->record($ingredient, 'adjustment', $delta, $request->user()->id, 'Stock count: '.$request->input('reason'));
            app(AuditLogService::class)->record($request, 'inventory.counted', $ingredient, ['stock' => $request->input('expected_stock')], ['stock' => $request->input('counted_stock'), 'reason' => $request->input('reason'), 'unit_cost' => $request->input('unit_cost')]);
            return $ingredient->fresh()->toArray();
        });
        return ['success' => true, 'data' => $result];
    }

    public function transfer(Request $request, OperationService $ops)
    {
        $branch = $ops->branch($request, 'inventory.adjust');
        $request->validate(['source_ingredient_id' => 'required|integer', 'destination_ingredient_id' => 'required|integer|different:source_ingredient_id', 'quantity' => 'required|numeric|gt:0|decimal:0,3', 'reason' => 'required|string|max:255']);
        $result = $ops->run($request, $branch, 'stock.transfer', function () use ($request, $branch) {
            // Lock both ingredient rows in deterministic order, also across branches.
            $rows = Ingredient::with('unit')->whereIn('id', [$request->integer('source_ingredient_id'), $request->integer('destination_ingredient_id')])->orderBy('id')->lockForUpdate()->get()->keyBy('id');
            $from = $rows->get($request->integer('source_ingredient_id'));
            $to = $rows->get($request->integer('destination_ingredient_id'));
            abort_unless($from && $to && $from->branch_id === $branch, 404, 'Accessible ingredients not found.');
            abort_unless($request->user()->can('branches.view-all') || $request->user()->branches()->where('branches.id', $to->branch_id)->exists(), 403, 'Destination branch access denied.');
            abort_if($from->branch_id === $to->branch_id, 422, 'Choose a different destination branch.');
            abort_unless($from->is_active && $to->is_active && mb_strtolower(trim($from->name)) === mb_strtolower(trim($to->name)), 422, 'Transfer requires matching active ingredients.');
            $quantity = (float) $request->input('quantity');
            abort_if($quantity > (float) $from->current_stock, 422, 'Transfer quantity exceeds source stock.');
            $converted = round(app(UnitConversionService::class)->convert($quantity, $from->unit, $to->unit), 3);
            abort_if($converted <= 0, 422, 'Converted quantity is below stock precision.');
            $sourceCost = $from->average_unit_cost;
            $reason = 'Transfer '.$request->input('uuid').': '.$request->input('reason');
            app(StockMovementService::class)->record($from, 'adjustment', -$quantity, $request->user()->id, $reason);
            app(StockMovementService::class)->record($to, 'adjustment', $converted, $request->user()->id, $reason, null, $sourceCost === null ? null : (float) $sourceCost * $quantity / $converted, $sourceCost === null);
            if ($sourceCost === null) $to->forceFill(['average_unit_cost' => null])->save();
            app(AuditLogService::class)->record($request, 'inventory.transferred', $from, null, ['destination_ingredient_id' => $to->id, 'quantity' => $quantity, 'received_quantity' => $converted, 'reason' => $reason]);
            return ['source' => $from->fresh()->toArray(), 'destination' => $to->fresh()->toArray()];
        });
        return ['success' => true, 'data' => $result];
    }
}
