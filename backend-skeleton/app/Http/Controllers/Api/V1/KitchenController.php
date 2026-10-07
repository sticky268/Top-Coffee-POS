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

        $tickets = KitchenTicket::query()
            ->with([
                'order:id,branch_id,user_id,customer_id,table_id,order_type,status,total,created_at',
                'order.table:id,name',
                'items:id,order_id,product_id,product_variant_id,quantity,unit_price,notes',
                'items.product:id,name',
                'items.variant:id,product_id,name',
                'items.modifiers',
            ])
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

        $ticket = KitchenTicket::query()
            ->with(['order' => fn ($query) => $query->withoutGlobalScope('branch')])
            ->whereKey($id)
            ->first();

        if (! $ticket) {
            return response()->json([
                'success' => false,
                'message' => 'Kitchen ticket not found.',
            ], 404);
        }

        $user = $request->user();
        $order = $ticket->order;

        $canAccessBranch = $user->can('branches.view-all')
            || $user->branches()->where('branches.id', $order->branch_id)->exists();

        if (! $canAccessBranch) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch.',
            ], 403);
        }

        // A cancelled ticket is immutable. Also reject status updates if the
        // parent order was cancelled after the kitchen screen loaded.
        if ($ticket->status === 'cancelled' || $order?->status === 'cancelled') {
            return response()->json([
                'success' => false,
                'message' => 'This order was cancelled. Kitchen preparation cannot continue.',
            ], 409);
        }

        $status = $request->input('status');

        $ticket->status = $status;

        if ($status === 'new') {
            $ticket->sent_at = null;
            $ticket->ready_at = null;
            $ticket->completed_at = null;
        } elseif ($status === 'preparing') {
            $ticket->sent_at ??= now();
            $ticket->ready_at = null;
            $ticket->completed_at = null;
        } elseif ($status === 'ready') {
            $ticket->sent_at ??= now();
            $ticket->ready_at = now();
            $ticket->completed_at = null;
        } elseif ($status === 'completed') {
            $ticket->sent_at ??= now();
            $ticket->ready_at ??= now();
            $ticket->completed_at = now();
        }

        $ticket->save();
        $ticket->refresh();

        return response()->json([
            'success' => true,
            'message' => 'Kitchen ticket status updated successfully.',
            'data' => $ticket,
        ]);
    }
}
