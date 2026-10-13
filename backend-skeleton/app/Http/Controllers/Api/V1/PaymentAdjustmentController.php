<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentRefund;
use App\Models\Ingredient;
use App\Models\StockMovement;
use App\Services\AuditLogService;
use App\Services\OperationService;
use App\Services\ShiftService;
use App\Services\SaleInventoryService;
use App\Services\StockMovementService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PaymentAdjustmentController extends Controller
{
    public function show(Request $request, int $id, OperationService $ops)
    {
        $branch = $ops->branch($request, 'orders.view');
        $order = Order::whereKey($id)->where('branch_id', $branch)->firstOrFail();
        return ['success' => true, 'data' => $this->summary($order)];
    }

    public function refund(Request $request, int $id, OperationService $ops)
    {
        $branch = $ops->branch($request, 'orders.refund');
        $request->validate(['amount' => 'required|numeric|gt:0|decimal:0,2', 'reason' => 'required|string|max:255', 'inventory_disposition' => 'required|in:consumed,restock,wastage']);
        $result = $ops->run($request, $branch, 'order.refund.'.$id, function () use ($request, $id, $branch) {
            $order = Order::whereKey($id)->where('branch_id', $branch)->lockForUpdate()->firstOrFail();
            abort_unless($order->status === 'completed', 409, 'Only a completed sale can be refunded.');
            $payments = $this->paymentRecords($order, true);
            $refunded = $payments->sum(fn ($p) => $p->refunds->sum(fn ($r) => OperationService::cents($r->amount)));
            $available = $payments->sum(fn ($p) => OperationService::cents($p->amount)) - $refunded;
            $remaining = OperationService::cents($request->input('amount'));
            abort_if($remaining > $available, 422, 'Refund exceeds the remaining paid amount.');
            $disposition = $request->input('inventory_disposition');
            abort_if($disposition !== 'consumed' && ($remaining !== $available || $refunded > 0 || $order->inventory_disposed_at), 422, 'Restock or wastage requires the first refund to cover the entire sale.');
            $shift = app(ShiftService::class)->active($branch, $request->user()->id);
            foreach ($payments as $payment) {
                if ($remaining === 0) break;
                $left = OperationService::cents($payment->amount) - $payment->refunds->sum(fn ($r) => OperationService::cents($r->amount));
                $portion = min($left, $remaining);
                if ($portion <= 0) continue;
                abort_if($payment->method === 'cash' && ! $shift, 409, 'Open your shift before issuing a cash refund.');
                if ($payment->method === 'cash') abort_if($portion > OperationService::cents(app(ShiftService::class)->summary($shift)['live_expected_cash']), 422, 'Refund exceeds expected cash in this drawer.');
                PaymentRefund::create(['payment_id' => $payment->id, 'amount' => $portion / 100, 'reason' => $request->input('reason'), 'processed_by' => $request->user()->id, 'shift_id' => $shift?->id, 'inventory_disposition' => $disposition]);
                $payment->update(['status' => $portion === $left ? 'refunded' : 'partially_refunded']);
                $remaining -= $portion;
            }
            if ($disposition !== 'consumed') {
                $deductions = StockMovement::where('reference_type', $order->getMorphClass())->where('reference_id', $order->id)->where('type', 'sale_deduction')->orderBy('ingredient_id')->get()->groupBy('ingredient_id');
                // Wastage reclassifies the original consumption. It must retain
                // its historical cost and leave today's remaining-stock valuation intact.
                $currentCosts = Ingredient::withTrashed()->whereIn('id', $deductions->keys())->orderBy('id')->lockForUpdate()->pluck('average_unit_cost', 'id');
                app(SaleInventoryService::class)->reverseForOrder($order, $request->user()->id);
                if ($disposition === 'wastage') {
                    foreach ($deductions as $ingredientId => $rows) {
                        $quantity = (float) $rows->sum('quantity');
                        if ($quantity >= 0) continue;
                        $ingredient = Ingredient::withTrashed()->findOrFail($ingredientId);
                        $unknown = $rows->contains(fn ($row) => $row->unit_cost === null);
                        $unitCost = $unknown ? null : $rows->sum(fn ($row) => (float) $row->quantity * (float) $row->unit_cost) / $quantity;
                        app(StockMovementService::class)->record($ingredient, 'wastage', $quantity, $request->user()->id, $request->input('reason'), $order, $unitCost, $unknown);
                        $ingredient->forceFill(['average_unit_cost' => $currentCosts->get($ingredientId)])->save();
                    }
                }
                $order->forceFill(['inventory_disposed_at' => now()])->save();
            }
            app(\App\Services\LoyaltyService::class)->reverseForOrder($order, $request->user()->id);
            app(AuditLogService::class)->record($request, 'order.refunded', $order, null, $request->only(['amount', 'reason', 'inventory_disposition']));
            return $this->summary($order);
        });
        return ['success' => true, 'data' => $result];
    }

    public function charge(Request $request, int $id, OperationService $ops)
    {
        $branch = $ops->branch($request, 'orders.refund');
        $request->validate(['amount' => 'required|numeric|gt:0|max:9999999.99|decimal:0,2', 'method' => 'required|in:cash,card,qr', 'tendered' => 'nullable|numeric|min:0|decimal:0,2', 'reason' => 'required|string|max:255']);
        $result = $ops->run($request, $branch, 'order.charge.'.$id, function () use ($request, $id, $branch) {
            $order = Order::whereKey($id)->where('branch_id', $branch)->lockForUpdate()->firstOrFail();
            abort_unless($order->status === 'completed', 409, 'Only a completed sale can receive an additional charge.');
            abort_if($order->payments()->whereHas('refunds')->exists(), 409, 'An already refunded sale cannot receive an additional charge.');
            $amount = OperationService::cents($request->input('amount'));
            $cash = $request->input('method') === 'cash';
            $tendered = OperationService::cents($request->input('tendered', $request->input('amount')));
            abort_if($cash && $tendered < $amount, 422, 'Cash received is less than the additional charge.');
            $shift = app(ShiftService::class)->active($branch, $request->user()->id);
            abort_if($cash && ! $shift, 409, 'Open your shift before collecting an additional cash payment.');
            Payment::create(['order_id' => $order->id, 'method' => $request->input('method'), 'amount' => $amount / 100, 'tendered' => $cash ? $tendered / 100 : null, 'change_due' => $cash ? ($tendered - $amount) / 100 : null, 'status' => 'completed', 'processed_by' => $request->user()->id, 'shift_id' => $shift?->id, 'reference' => $request->input('uuid')]);
            $order->forceFill(['supplemental_total' => (OperationService::cents($order->supplemental_total) + $amount) / 100])->save();
            app(AuditLogService::class)->record($request, 'order.additional_charge', $order, null, $request->only(['amount', 'method', 'reason']));
            return $this->summary($order);
        });
        return ['success' => true, 'data' => $result];
    }

    private function paymentRecords(Order $order, bool $lock): \Illuminate\Support\Collection
    {
        $query = $order->payments()->orderBy('id');
        if ($lock) $query->lockForUpdate();
        $payments = $query->get();
        $query = PaymentRefund::whereIn('payment_id', $payments->pluck('id'))->orderBy('id');
        // InnoDB repeatable-read snapshots may predate a waited-on order lock.
        // Read refund rows with locks too, so limits and responses see committed corrections.
        if ($lock) $query->lockForUpdate();
        $refunds = $query->get()->groupBy('payment_id');
        foreach ($payments as $payment) $payment->setRelation('refunds', $refunds->get($payment->id, collect()));
        return $payments;
    }

    private function summary(Order $order): array
    {
        $payments = $this->paymentRecords($order, DB::transactionLevel() > 0);
        $paid = $payments->sum(fn ($p) => OperationService::cents($p->amount));
        $refunded = $payments->sum(fn ($p) => $p->refunds->sum(fn ($r) => OperationService::cents($r->amount)));
        return ['order_id' => $order->id, 'paid' => $paid / 100, 'refunded' => $refunded / 100, 'net_paid' => ($paid - $refunded) / 100, 'supplemental_total' => (float) $order->supplemental_total, 'payments' => $payments->toArray()];
    }
}
