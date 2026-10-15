<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\OperationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CashDrawerEventController extends Controller
{
    /** Telemetry only: this endpoint cannot open hardware or change cash totals. */
    public function store(Request $request, OperationService $operations, AuditLogService $audit)
    {
        $branch = $operations->branch($request, 'orders.create');
        $input = $request->validate([
            'event_uuid' => 'required|uuid',
            'expected_user_id' => 'required|integer|min:1',
            'source' => 'required|in:manual,cash_sale',
            'order_id' => 'nullable|integer|min:1|required_if:source,cash_sale|prohibited_if:source,manual',
            'reason' => 'required_if:source,manual|nullable|string|min:3|max:255',
            'status' => 'required|in:attempt_recorded,command_sent,unconfirmed',
            'device_requested_at' => 'required|string|max:40|date',
            'device_finished_at' => 'nullable|string|max:40|date|required_unless:status,attempt_recorded',
            'physical_open_confirmed' => 'prohibited',
            'business_id' => 'prohibited',
            'user_id' => 'prohibited',
        ]);
        abort_unless($request->integer('expected_user_id') === $request->user()->id, 403,
            'The original cashier must upload this drawer request.');
        $immutable = [
            'business_id' => $request->user()->business_id,
            'branch_id' => $branch,
            'user_id' => $request->user()->id,
            'source' => $input['source'],
            'order_id' => $input['source'] === 'cash_sale' ? (int) $input['order_id'] : null,
            'reason' => $input['source'] === 'cash_sale' ? 'Completed cash sale' : trim($input['reason']),
            'device_requested_at' => $input['device_requested_at'],
        ];
        abort_if(strlen($immutable['reason']) < 3, 422, 'Enter a reason for manual drawer access.');

        $result = DB::transaction(function () use ($request, $input, $immutable, $audit) {
            // Serialize retries for this actor, including concurrent first uploads.
            User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
            $key = ['user_id' => $request->user()->id, 'event_uuid' => $input['event_uuid']];
            $previous = DB::table('cash_drawer_events')->where($key)->first();
            if ($previous) {
                foreach ($immutable as $field => $value) {
                    abort_unless((string) $previous->$field === (string) $value, 409,
                        'This drawer reference was already used with different details.');
                }
                if ($previous->status !== 'attempt_recorded') {
                    // A delayed initial upload must not downgrade a final result.
                    abort_if($input['status'] !== 'attempt_recorded' && (
                        $previous->status !== $input['status'] ||
                        $previous->device_finished_at !== ($input['device_finished_at'] ?? null)
                    ), 409, 'The recorded drawer result cannot be changed.');
                    return $this->result($previous);
                }
                if ($input['status'] === 'attempt_recorded') return $this->result($previous);
            } elseif ($immutable['order_id'] !== null) {
                $order = Order::withTrashed()->whereKey($immutable['order_id'])
                    ->where('branch_id', $immutable['branch_id'])->where('status', 'completed')->firstOrFail();
                // Held orders can be settled by another cashier; use the payment actor.
                // Refunded historical payments remain valid telemetry after offline delay.
                abort_unless($order->payments()->where('processed_by', $immutable['user_id'])
                    ->where('method', 'cash')->where('amount', '>', 0)
                    ->whereIn('status', ['completed', 'partially_refunded', 'refunded'])->exists(),
                    422, 'Automatic drawer requests require a confirmed cash payment by this cashier.');
            }
            $values = [
                'status' => $input['status'],
                'device_finished_at' => $input['status'] === 'attempt_recorded'
                    ? null : $input['device_finished_at'],
                'updated_at' => now(),
            ];
            if ($previous) {
                DB::table('cash_drawer_events')->where('id', $previous->id)->update($values);
                $id = $previous->id;
            } else {
                $id = DB::table('cash_drawer_events')->insertGetId(
                    $key + $immutable + $values + ['created_at' => now()]
                );
            }
            $audit->record($request, 'cash_drawer.'.$input['status'], null, null,
                $immutable + ['event_uuid' => $input['event_uuid'], 'status' => $input['status'],
                    'device_finished_at' => $values['device_finished_at'],
                    'evidence' => 'device_reported_command_only', 'physical_open_confirmed' => false]);
            return $this->result(DB::table('cash_drawer_events')->where('id', $id)->first());
        }, 3);

        return ['success' => true, 'data' => $result];
    }

    private function result(object $event): array
    {
        return [
            'event_uuid' => $event->event_uuid,
            'status' => $event->status,
            'evidence' => 'device_reported_command_only',
            'physical_open_confirmed' => false,
            'received_at' => $event->created_at,
        ];
    }
}
