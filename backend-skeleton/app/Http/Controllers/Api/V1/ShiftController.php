<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CashierShift;
use App\Services\AuditLogService;
use App\Services\OperationService;
use App\Services\ShiftService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ShiftController extends Controller
{
    public function index(Request $request, OperationService $ops, ShiftService $service)
    {
        $branch = $ops->branch($request, $request->user()->can('orders.create') ? 'orders.create' : ($request->user()->can('orders.refund') ? 'orders.refund' : 'reports.view'));
        $query = CashierShift::with('cashier')->where('branch_id', $branch);
        if (! $request->user()->can('reports.view')) $query->where('user_id', $request->user()->id);
        return ['success' => true, 'data' => $query->orderByDesc('id')->limit(50)->get()->map(fn ($s) => $service->summary($s))];
    }

    public function open(Request $request, OperationService $ops, ShiftService $service)
    {
        $branch = $ops->branch($request, $request->user()->can('orders.create') ? 'orders.create' : 'orders.refund');
        $request->validate(['opening_cash' => 'required|numeric|min:0|max:9999999.99|decimal:0,2']);
        $result = $ops->run($request, $branch, 'shift.open', function () use ($request, $branch, $service) {
            abort_if($service->active($branch, $request->user()->id), 409, 'Close your current shift before opening another.');
            $shift = CashierShift::create(['branch_id' => $branch, 'user_id' => $request->user()->id, 'opening_cash' => $request->input('opening_cash')]);
            app(AuditLogService::class)->record($request, 'shift.opened', $shift, null, $shift->toArray());
            return $service->summary($shift);
        });
        return response()->json(['success' => true, 'data' => $result], 201);
    }

    public function movement(Request $request, int $id, OperationService $ops, ShiftService $service)
    {
        $branch = $ops->branch($request, $request->user()->can('orders.create') ? 'orders.create' : 'orders.refund');
        $request->validate(['type' => 'required|in:in,out', 'amount' => 'required|numeric|gt:0|max:9999999.99|decimal:0,2', 'reason' => 'required|string|max:255']);
        $result = $ops->run($request, $branch, 'shift.movement.'.$id, function () use ($request, $id, $branch, $service) {
            $shift = $this->ownOpen($request, $id, $branch);
            abort_if($request->input('type') === 'out' && (float) $request->input('amount') > $service->summary($shift)['live_expected_cash'], 422, 'Cash out exceeds expected drawer cash.');
            DB::table('cash_movements')->insert(['shift_id' => $shift->id, 'type' => $request->input('type'), 'amount' => $request->input('amount'), 'reason' => $request->input('reason'), 'created_at' => now(), 'updated_at' => now()]);
            app(AuditLogService::class)->record($request, 'shift.cash_movement', $shift, null, $request->only(['type', 'amount', 'reason']));
            return $service->summary($shift);
        });
        return ['success' => true, 'data' => $result];
    }

    public function close(Request $request, int $id, OperationService $ops, ShiftService $service)
    {
        $branch = $ops->branch($request, $request->user()->can('orders.create') ? 'orders.create' : 'orders.refund');
        $request->validate(['counted_cash' => 'required|numeric|min:0|max:9999999.99|decimal:0,2', 'reason' => 'nullable|string|max:1000']);
        $result = $ops->run($request, $branch, 'shift.close.'.$id, function () use ($request, $id, $branch, $service) {
            $shift = $this->ownOpen($request, $id, $branch);
            $expected = $service->summary($shift)['live_expected_cash'];
            $difference = (OperationService::cents($request->input('counted_cash')) - OperationService::cents($expected)) / 100;
            abort_if($difference != 0 && blank($request->input('reason')), 422, 'Explain the cash difference before closing.');
            $shift->update(['status' => 'closed', 'expected_cash' => $expected, 'counted_cash' => $request->input('counted_cash'), 'difference' => $difference, 'closing_reason' => $request->input('reason'), 'closed_at' => now()]);
            app(AuditLogService::class)->record($request, 'shift.closed', $shift, null, $shift->toArray());
            return $service->summary($shift);
        });
        return ['success' => true, 'data' => $result];
    }

    public function review(Request $request, int $id, OperationService $ops, ShiftService $service)
    {
        $branch = $ops->branch($request, 'reports.view');
        $result = $ops->run($request, $branch, 'shift.review.'.$id, function () use ($request, $id, $branch, $service) {
            $shift = CashierShift::whereKey($id)->where('branch_id', $branch)->lockForUpdate()->firstOrFail();
            abort_unless($shift->status === 'closed', 409, 'Only a closed shift can be reviewed.');
            abort_if($shift->reviewed_at, 409, 'This shift is already reviewed.');
            $shift->update(['reviewed_by' => $request->user()->id, 'reviewed_at' => now()]);
            app(AuditLogService::class)->record($request, 'shift.reviewed', $shift);
            return $service->summary($shift);
        });
        return ['success' => true, 'data' => $result];
    }

    private function ownOpen(Request $request, int $id, int $branch): CashierShift
    {
        $shift = CashierShift::whereKey($id)->where('branch_id', $branch)->where('user_id', $request->user()->id)->lockForUpdate()->firstOrFail();
        abort_unless($shift->status === 'open', 409, 'This shift is already closed.');
        return $shift;
    }
}
