<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\KitchenTicket;
use Illuminate\Http\Request;

class KitchenController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('kitchen.view')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $user = $request->user();
        $branchId = $request->input('branch_id');

        if ($branchId !== null) {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to this branch.',
                ], 403);
            }
        } else {
            $branchId = $user->branches()->orderBy('branches.id')->value('branches.id');
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $kitchenEnabled = (bool) \App\Models\Branch::query()
            ->whereKey($branchId)
            ->value('use_kitchen_display');

        if (! $kitchenEnabled) {
            return response()->json([
                'success' => true,
                'data' => [],
                'kitchen_enabled' => false,
            ]);
        }

        $tickets = KitchenTicket::query()
            ->with([
                'order:id,branch_id,user_id,customer_id,table_id,order_type,status,total,created_at',
                'order.table:id,name',
                'items:id,order_id,product_id,product_variant_id,quantity,unit_price,notes',
                'items.product:id,name',
                'items.variant:id,product_id,name',
                'items.modifiers',
            ])
            ->whereNull('cancellation_acknowledged_at')
            ->whereHas('order', function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            })
            ->orderByRaw("
                CASE status
                    WHEN 'new' THEN 1
                    WHEN 'preparing' THEN 2
                    WHEN 'ready' THEN 3
                    WHEN 'completed' THEN 4
                    WHEN 'cancelled' THEN 5
                    ELSE 6
                END
            ")
            ->orderBy('created_at')
            ->get();

        // Keep the existing Flutter response shape (ticket.order.items),
        // but populate it with only the items submitted in this ticket.
        foreach ($tickets as $ticket) {
            $items = $ticket->items->map(function ($item) {
                $item->quantity = (int) $item->pivot->quantity;
                $item->unsetRelation('pivot');
                return $item;
            });
            // Eloquent can reuse the same Order instance for multiple tickets.
            // Clone it so each ticket retains its own item batch in JSON.
            $order = clone $ticket->order;
            $order->setRelation('items', $items);
            $ticket->setRelation('order', $order);
            $ticket->unsetRelation('items');
        }

        return response()->json([
            'success' => true,
            'data' => $tickets,
        ]);
    }

    public function updateStatus(Request $request, $id)
    {
        if (! $request->user()->can('kitchen.update-status')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $validator = \Illuminate\Support\Facades\Validator::make(
            $request->all(),
            [
                'status' => [
                    'required',
                    'string',
                    'in:new,preparing,ready,completed',
                ],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $status = $request->input('status');

        $result = \Illuminate\Support\Facades\DB::transaction(function () use ($id, $user, $status) {
            // Lock the order before its ticket, matching the cancellation
            // transaction's lock order. This serializes cancellation and
            // kitchen progress without risking an opposite-order deadlock.
            $orderId = KitchenTicket::query()->whereKey($id)->value('order_id');
            if ($orderId === null) {
                return ['error' => 'Kitchen ticket not found.', 'code' => 404];
            }

            $order = \App\Models\Order::query()
                ->withoutGlobalScope('branch')
                ->whereKey($orderId)
                ->lockForUpdate()
                ->first();

            if (! $order) {
                return ['error' => 'Kitchen ticket not found.', 'code' => 404];
            }

            $ticket = KitchenTicket::query()
                ->whereKey($id)
                ->lockForUpdate()
                ->first();

            if (! $ticket || (int) $ticket->order_id !== (int) $order->id) {
                return ['error' => 'Kitchen ticket not found.', 'code' => 404];
            }
            if (! $user->can('branches.view-all')
                && ! $user->branches()->where('branches.id', $order->branch_id)->exists()) {
                return ['error' => 'You do not have access to this branch.', 'code' => 403];
            }

            if ($ticket->status === 'cancelled' || $order->status === 'cancelled') {
                return ['error' => 'This order was cancelled. Kitchen preparation cannot continue.', 'code' => 409];
            }

            $next = [
                'new' => 'preparing',
                'preparing' => 'ready',
                'ready' => 'completed',
            ];

            if (($next[$ticket->status] ?? null) !== $status) {
                return ['error' => 'Invalid kitchen status transition. Refresh the kitchen display.', 'code' => 409];
            }

            $ticket->status = $status;
            if ($status === 'preparing') {
                $ticket->sent_at ??= now();
            } elseif ($status === 'ready') {
                $ticket->ready_at = now();
            } elseif ($status === 'completed') {
                $ticket->completed_at = now();
            }
            $ticket->save();

            return ['ticket' => $ticket->fresh()];
        });

        if (isset($result['error'])) {
            return response()->json([
                'success' => false,
                'message' => $result['error'],
            ], $result['code']);
        }

        $ticket = $result['ticket'];

        return response()->json([
            'success' => true,
            'message' => 'Kitchen ticket status updated successfully.',
            'data' => $ticket,
        ]);
    }
    /**
     * Acknowledge a cancellation without deleting the ticket or order history.
     */
    public function acknowledgeCancellation(Request $request, int $id)
    {
        if (! $request->user()->can('kitchen.update-status')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $ticket = KitchenTicket::query()
            ->with(['order' => fn ($query) => $query->withoutGlobalScope('branch')])
            ->find($id);

        if (! $ticket || ! $ticket->order) {
            return response()->json(['success' => false, 'message' => 'Kitchen ticket not found.'], 404);
        }

        $user = $request->user();
        $branchId = $ticket->order->branch_id;
        if (! $user->can('branches.view-all')
            && ! $user->branches()->where('branches.id', $branchId)->exists()) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if ($ticket->status !== 'cancelled' && $ticket->order->status !== 'cancelled') {
            return response()->json([
                'success' => false,
                'message' => 'Only cancelled kitchen tickets can be acknowledged.',
            ], 409);
        }

        if ($ticket->cancellation_acknowledged_at === null) {
            $ticket->update([
                'status' => 'cancelled',
                'cancellation_acknowledged_at' => now(),
            ]);
        }

        return response()->json([
            'success' => true,
            'data' => ['id' => $ticket->id, 'acknowledged' => true],
        ]);
    }

}
