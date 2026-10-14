<?php

namespace App\Services;

use App\Models\CashierShift;
use Illuminate\Support\Facades\DB;

class ShiftService
{
    public function active(int $branch, int $user): ?CashierShift
    {
        return CashierShift::where('branch_id', $branch)->where('user_id', $user)->where('status', 'open')->lockForUpdate()->first();
    }

    public function paymentShift(int $branch, int $user): ?int
    {
        // Offline requests must retain their original shift; never silently
        // charge a later shift when the saved request finally reaches the server.
        $request = request();
        $request->validate(['shift_id' => 'nullable|integer|min:1']);
        if ($request->exists('shift_id') && $request->input('shift_id') === null) return null;
        if ($request->filled('shift_id')) {
            $shift = CashierShift::whereKey($request->integer('shift_id'))->where('branch_id', $branch)->where('user_id', $user)->lockForUpdate()->first();
            abort_unless($shift && $shift->status === 'open', 409, 'The original shift is closed or unavailable. Reconcile this payment with a manager.');
            return $shift->id;
        }
        if ($request->filled('created_offline_at')) return null;
        return $this->active($branch, $user)?->id;
    }

    public function summary(CashierShift $shift): array
    {
        $payments = DB::table('payments')->where('shift_id', $shift->id)->whereIn('status', ['completed', 'partially_refunded', 'refunded'])->orderBy('id');
        $refunds = DB::table('payment_refunds')->join('payments', 'payments.id', '=', 'payment_refunds.payment_id')->where('payment_refunds.shift_id', $shift->id)->select('payment_refunds.*', 'payments.method')->orderBy('payment_refunds.id');
        $movements = DB::table('cash_movements')->where('shift_id', $shift->id)->orderBy('id');
        if (DB::transactionLevel() > 0) {
            // Current reads after waiting on the shift lock prevent stale drawer totals.
            $payments->lockForUpdate(); $refunds->lockForUpdate(); $movements->lockForUpdate();
        }
        $payments = $payments->get();
        $refunds = $refunds->get();
        $movements = $movements->get();
        $cash = $payments->where('method', 'cash')->sum(fn ($p) => OperationService::cents($p->amount));
        $cashRefunds = $refunds->where('method', 'cash')->sum(fn ($r) => OperationService::cents($r->amount));
        $in = $movements->where('type', 'in')->sum(fn ($m) => OperationService::cents($m->amount));
        $out = $movements->where('type', 'out')->sum(fn ($m) => OperationService::cents($m->amount));
        return $shift->toArray() + [
            'cash_sales' => $cash / 100, 'cash_refunds' => $cashRefunds / 100,
            'cash_in' => $in / 100, 'cash_out' => $out / 100,
            'live_expected_cash' => (OperationService::cents($shift->opening_cash) + $cash - $cashRefunds + $in - $out) / 100,
            'payment_totals' => $payments->groupBy('method')->map(fn ($rows, $method) => ['method' => $method, 'amount' => $rows->sum(fn ($p) => OperationService::cents($p->amount)) / 100])->values()->all(),
            'movements' => $movements->toArray(),
        ];
    }
}
