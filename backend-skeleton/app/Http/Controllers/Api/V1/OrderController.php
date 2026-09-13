<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Models\Product;
use App\Models\ProductVariant;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Throwable;

class OrderController extends Controller
{
    /**
     * POST /api/v1/orders
     *
     * Creates an order + its items + its payment inside a single DB
     * transaction Ã¢â‚¬â€ the Phase 1 architecture requirement that a payment
     * succeeding while another write fails must never leave inconsistent
     * records. Every line's price is recomputed server-side from
     * Product/ProductVariant + the resolved branch's branch_product pivot
     * (identical resolution logic to ProductController::index()) rather
     * than trusting whatever price the Flutter cart submits Ã¢â‚¬â€ a client
     * payload is a request, not a source of truth, for anything touching
     * payment amounts.
     *
     * Requires the 'orders.create' permission (already seeded on the
     * cashier role, and implicitly on admin via branches.view-all's
     * sibling grant of all permissions). Note: the existing manager role
     * does NOT have 'orders.create' in RolePermissionSeeder Ã¢â‚¬â€ a
     * pre-existing seeder gap, not introduced or fixed here.
     *
     * Deliberately NOT implemented here (out of scope for this task):
     * inventory deduction, recipes, kitchen tickets, tax calculation,
     * table/dine-in selection beyond the raw order_type field.
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('orders.create')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to create orders',
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
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        } else {
            $branch = $user->branches()->wherePivot('is_primary', true)->first()
                ?? $user->branches()->first();

            if (! $branch) {
                return response()->json([
                    'success' => false,
                    'message' => 'No branch is assigned to this user',
                ], 422);
            }

            $branchId = $branch->id;
        }
        
        $validator = Validator::make($request->all(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'order_type' => 'required|in:dine_in,takeaway',
            'table_id' => 'nullable|integer|exists:restaurant_tables,id|required_if:order_type,dine_in',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.quantity' => 'required|integer|min:1',
            'discount_total' => 'nullable|numeric|min:0',
            'payment.method' => 'required|in:cash,card,qr',
            'payment.tendered' => 'nullable|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $discountTotal = round((float) $request->input('discount_total', 0), 2);
        $paymentMethod = $request->input('payment.method');
        $tendered = $request->input('payment.tendered');

        try {
            $order = DB::transaction(function () use (
                $request, $user, $branchId, $discountTotal, $paymentMethod, $tendered
            ) {
                $subtotal = 0;
                $resolvedItems = [];

                foreach ($request->input('items') as $itemInput) {
                    $product = Product::query()
                        ->where('is_active', true)
                        ->whereHas('branches', function ($query) use ($branchId) {
                            $query->where('branches.id', $branchId)
                                ->where('branch_product.is_available', true);
                        })
                        ->with(['branches' => function ($query) use ($branchId) {
                            $query->where('branches.id', $branchId);
                        }])
                        ->find($itemInput['product_id']);

                    if (! $product) {
                        // Aborting here rolls back the whole transaction Ã¢â‚¬â€
                        // no partial order is ever left behind because one
                        // line referenced an unavailable product.
                        abort(422, "Product {$itemInput['product_id']} is not available at this branch.");
                    }

                    $branchPivot = $product->branches->first()?->pivot;
                    $effectivePrice = ($branchPivot && $branchPivot->price_override !== null)
                        ? (float) $branchPivot->price_override
                        : (float) $product->base_price;

                    $unitPrice = $effectivePrice;
                    $variantId = $itemInput['product_variant_id'] ?? null;

                    if ($variantId !== null) {
                        $variant = ProductVariant::query()
                            ->where('id', $variantId)
                            ->where('product_id', $product->id)
                            ->where('is_active', true)
                            ->first();

                        if (! $variant) {
                            abort(422, "Variant {$variantId} is not valid for product {$product->id}.");
                        }

                        $unitPrice = $effectivePrice + (float) $variant->price_delta;
                    }

                    $quantity = (int) $itemInput['quantity'];
                    $subtotal += $unitPrice * $quantity;

                    $resolvedItems[] = [
                        'product_id' => $product->id,
                        'product_variant_id' => $variantId,
                        'quantity' => $quantity,
                        'unit_price' => $unitPrice,
                    ];
                }

                $total = max(0, round($subtotal - $discountTotal, 2));

                $order = Order::create([
                    'uuid' => (string) Str::uuid(),
                    'branch_id' => $branchId,
                    'user_id' => $user->id,
                    'order_type' => $request->input('order_type'),
                    'table_id' => $request->input('table_id'),
                    // No kitchen/hold workflow yet (Phase 10/11 territory)
                    // Ã¢â‚¬â€ payment confirmation marks the order completed
                    // immediately.
                    'status' => 'completed',
                    'subtotal' => round($subtotal, 2),
                    'discount_total' => $discountTotal,
                    'tax_total' => 0,
                    'total' => $total,
                    'completed_at' => now(),
                ]);

                foreach ($resolvedItems as $item) {
                    OrderItem::create(array_merge($item, ['order_id' => $order->id]));
                }

                $changeDue = null;
                if ($paymentMethod === 'cash' && $tendered !== null) {
                    $changeDue = round((float) $tendered - $total, 2);
                }

                Payment::create([
                    'order_id' => $order->id,
                    'method' => $paymentMethod,
                    'amount' => $total,
                    'tendered' => $paymentMethod === 'cash' ? $tendered : null,
                    'change_due' => $changeDue,
                    'status' => 'completed',
                    'processed_by' => $user->id,
                ]);

                return $order->load(['items', 'payments']);
            });
        } catch (HttpException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getStatusCode());
        } catch (Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not create the order. Please try again.',
            ], 500);
        }

        $payment = $order->payments->first();

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'payment' => [
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null ? (float) $payment->tendered : null,
                    'change_due' => $payment->change_due !== null ? (float) $payment->change_due : null,
                ],
            ],
        ], 201);
    }

    /**
     * GET /api/v1/orders?branch_id=&order_number=&date_from=&date_to=&status=&payment_method=&per_page=&page=
     *
     * Branch scoping has two layers, deliberately not redundant with each
     * other:
     *  1. The Order model's existing BranchScoped trait always restricts
     *     Order::query() to the authenticated user's own branches (or
     *     leaves it unrestricted for branches.view-all holders) Ã¢â‚¬â€ this
     *     alone already makes it impossible for a user to see another
     *     branch's orders, with or without the parameter below.
     *  2. The new `branch_id` param ADDITIONALLY narrows within that
     *     already-safe set, to a single branch Ã¢â‚¬â€ this is what lets a
     *     multi-branch user (e.g. an admin switching branches in the
     *     Flutter app) scope the list to just the branch they're
     *     currently viewing, rather than always seeing every branch they
     *     have access to at once. An explicit 403 (matching Category/
     *     Product/Order-create's existing convention) is returned for a
     *     branch_id the user doesn't have access to, rather than
     *     silently returning zero rows Ã¢â‚¬â€ that ambiguity (no access vs.
     *     genuinely empty) is worse for a UI to interpret correctly.
     *
     * "order_number" matches this app's existing convention (see
     * OrderController::store()'s response and the Flutter checkout
     * confirmation screen) of using the numeric `id` as the user-facing
     * order number Ã¢â‚¬â€ there is no separate order_number column. A numeric
     * value matches `id` exactly; anything else is matched against `uuid`
     * as a partial search.
     */
    /**
     * POST /api/v1/orders/hold
     *
     * Saves a dine-in order without payment and marks its table occupied.
     */
    public function hold(Request $request)
    {
        if (! $request->user()->can('orders.create')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to create orders',
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
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        } else {
            $branch = $user->branches()->wherePivot('is_primary', true)->first()
                ?? $user->branches()->first();

            if (! $branch) {
                return response()->json([
                    'success' => false,
                    'message' => 'No branch is assigned to this user',
                ], 422);
            }

            $branchId = $branch->id;
        }

        $validator = Validator::make($request->all(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'order_type' => 'required|in:dine_in',
            'table_id' => 'required|integer|exists:restaurant_tables,id',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.quantity' => 'required|integer|min:1',
            'discount_total' => 'nullable|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed: ' . json_encode($validator->errors()->toArray()),
                'errors' => $validator->errors(),
            ], 422);
        }

        try {
            $order = DB::transaction(function () use ($request, $user, $branchId) {
                $table = \App\Models\RestaurantTable::query()
                    ->where('branch_id', $branchId)
                    ->where('id', $request->input('table_id'))
                    ->lockForUpdate()
                    ->first();

                if (! $table) {
                    abort(422, 'The selected table is not available at this branch.');
                }

                if ($table->status !== 'available') {
                    abort(422, 'The selected table is not available.');
                }

                $subtotal = 0;
                $resolvedItems = [];

                foreach ($request->input('items') as $itemInput) {
                    $product = Product::query()
                        ->where('is_active', true)
                        ->whereHas('branches', function ($query) use ($branchId) {
                            $query->where('branches.id', $branchId)
                                ->where('branch_product.is_available', true);
                        })
                        ->with(['branches' => function ($query) use ($branchId) {
                            $query->where('branches.id', $branchId);
                        }])
                        ->find($itemInput['product_id']);

                    if (! $product) {
                        abort(422, "Product {$itemInput['product_id']} is not available at this branch.");
                    }

                    $branchPivot = $product->branches->first()?->pivot;
                    $effectivePrice = ($branchPivot && $branchPivot->price_override !== null)
                        ? (float) $branchPivot->price_override
                        : (float) $product->base_price;

                    $unitPrice = $effectivePrice;
                    $variantId = $itemInput['product_variant_id'] ?? null;

                    if ($variantId !== null) {
                        $variant = ProductVariant::query()
                            ->where('id', $variantId)
                            ->where('product_id', $product->id)
                            ->where('is_active', true)
                            ->first();

                        if (! $variant) {
                            abort(422, "Variant {$variantId} is not valid for product {$product->id}.");
                        }

                        $unitPrice = $effectivePrice + (float) $variant->price_delta;
                    }

                    $quantity = (int) $itemInput['quantity'];
                    $subtotal += $unitPrice * $quantity;

                    $resolvedItems[] = [
                        'product_id' => $product->id,
                        'product_variant_id' => $variantId,
                        'quantity' => $quantity,
                        'unit_price' => $unitPrice,
                    ];
                }

                $discountTotal = round((float) $request->input('discount_total', 0), 2);
                $total = max(0, round($subtotal - $discountTotal, 2));

                $order = Order::create([
                    'uuid' => (string) Str::uuid(),
                    'branch_id' => $branchId,
                    'user_id' => $user->id,
                    'order_type' => 'dine_in',
                    'table_id' => $table->id,
                    'status' => 'held',
                    'subtotal' => round($subtotal, 2),
                    'discount_total' => $discountTotal,
                    'tax_total' => 0,
                    'total' => $total,
                    'held_at' => now(),
                ]);

                foreach ($resolvedItems as $item) {
                    OrderItem::create(array_merge($item, ['order_id' => $order->id]));
                }

                $table->update([
                    'status' => 'occupied',
                ]);

                return $order->load(['items']);
            });
        } catch (HttpException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getStatusCode());
        } catch (Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not save the order. Please try again.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'table_id' => $order->table_id,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'held_at' => $order->held_at?->toIso8601String(),
            ],
        ], 201);
    }

    /**
     * PATCH /api/v1/orders/{id}/hold
     *
     * Updates an existing held dine-in order without creating a new order.
     * Recalculates prices server-side and keeps the table occupied.
     */
    public function updateHeld(Request $request, int $id)
    {
        if (! $request->user()->can('orders.create')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to update orders',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.quantity' => 'required|integer|min:1',
            'discount_total' => 'nullable|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();

        try {
            $order = DB::transaction(function () use ($request, $user, $id) {
                $order = Order::query()
                    ->where('id', $id)
                    ->where('status', 'held')
                    ->where('order_type', 'dine_in')
                    ->lockForUpdate()
                    ->first();

                if (! $order) {
                    abort(404, 'Held order not found.');
                }

                if (! $user->can('branches.view-all')
                    && ! $user->branches()->where('branches.id', $order->branch_id)->exists()) {
                    abort(403, 'You do not have access to this branch.');
                }

                $table = \App\Models\RestaurantTable::query()
                    ->where('branch_id', $order->branch_id)
                    ->where('id', $order->table_id)
                    ->lockForUpdate()
                    ->first();

                if (! $table) {
                    abort(422, 'The order table could not be found.');
                }

                $subtotal = 0;
                $resolvedItems = [];

                foreach ($request->input('items') as $itemInput) {
                    $product = Product::query()
                        ->where('is_active', true)
                        ->whereHas('branches', function ($query) use ($order) {
                            $query->where('branches.id', $order->branch_id)
                                ->where('branch_product.is_available', true);
                        })
                        ->with(['branches' => function ($query) use ($order) {
                            $query->where('branches.id', $order->branch_id);
                        }])
                        ->find($itemInput['product_id']);

                    if (! $product) {
                        abort(422, "Product {$itemInput['product_id']} is not available at this branch.");
                    }

                    $branchPivot = $product->branches->first()?->pivot;
                    $effectivePrice = ($branchPivot && $branchPivot->price_override !== null)
                        ? (float) $branchPivot->price_override
                        : (float) $product->base_price;

                    $unitPrice = $effectivePrice;
                    $variantId = $itemInput['product_variant_id'] ?? null;

                    if ($variantId !== null) {
                        $variant = ProductVariant::query()
                            ->where('id', $variantId)
                            ->where('product_id', $product->id)
                            ->where('is_active', true)
                            ->first();

                        if (! $variant) {
                            abort(422, "Variant {$variantId} is not valid for product {$product->id}.");
                        }

                        $unitPrice = $effectivePrice + (float) $variant->price_delta;
                    }

                    $quantity = (int) $itemInput['quantity'];
                    $subtotal += $unitPrice * $quantity;

                    $resolvedItems[] = [
                        'product_id' => $product->id,
                        'product_variant_id' => $variantId,
                        'quantity' => $quantity,
                        'unit_price' => $unitPrice,
                    ];
                }

                $discountTotal = round((float) $request->input('discount_total', 0), 2);
                $total = max(0, round($subtotal - $discountTotal, 2));

                $order->update([
                    'subtotal' => round($subtotal, 2),
                    'discount_total' => $discountTotal,
                    'tax_total' => 0,
                    'total' => $total,
                    'held_at' => $order->held_at ?? now(),
                ]);

                $order->items()->delete();

                foreach ($resolvedItems as $item) {
                    OrderItem::create(array_merge($item, [
                        'order_id' => $order->id,
                    ]));
                }

                if ($table->status !== 'occupied') {
                    $table->update([
                        'status' => 'occupied',
                    ]);
                }

                return $order->load(['items']);
            });
        } catch (HttpException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getStatusCode());
        } catch (Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not update the order. Please try again.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'table_id' => $order->table_id,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'held_at' => $order->held_at?->toIso8601String(),
            ],
        ]);
    }
    /**
     * POST /api/v1/orders/{id}/pay
     *
     * Completes an existing held dine-in order and releases its table.
     */
    public function payHeld(Request $request, int $id)
    {
        if (! $request->user()->can('orders.create')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to pay orders',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'payment.method' => 'required|in:cash,card,qr',
            'payment.tendered' => 'nullable|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $paymentMethod = $request->input('payment.method');
        $tenderedInput = $request->input('payment.tendered');

        try {
            $result = DB::transaction(function () use (
                $request,
                $user,
                $id,
                $paymentMethod,
                $tenderedInput
            ) {
                $order = Order::query()
                    ->where('id', $id)
                    ->where('status', 'held')
                    ->where('order_type', 'dine_in')
                    ->lockForUpdate()
                    ->first();

                if (! $order) {
                    abort(404, 'Held order not found.');
                }

                if (! $user->can('branches.view-all')
                    && ! $user->branches()->where('branches.id', $order->branch_id)->exists()) {
                    abort(403, 'You do not have access to this branch.');
                }

                $table = \App\Models\RestaurantTable::query()
                    ->where('branch_id', $order->branch_id)
                    ->where('id', $order->table_id)
                    ->lockForUpdate()
                    ->first();

                if (! $table) {
                    abort(422, 'The order table could not be found.');
                }

                $total = round((float) $order->total, 2);
                $tendered = $tenderedInput !== null
                    ? round((float) $tenderedInput, 2)
                    : null;

                if ($paymentMethod === 'cash') {
                    // If no cash amount is entered, treat it as exact payment.
                    if ($tendered === null) {
                        $tendered = $total;
                    }

                    if ($tendered < $total) {
                        abort(422, 'Cash tendered is less than the order total.');
                    }

                    $changeDue = round($tendered - $total, 2);
                } else {
                    $tendered = null;
                    $changeDue = 0;
                }

                $payment = Payment::create([
                    'order_id' => $order->id,
                    'method' => $paymentMethod,
                    'amount' => $total,
                    'tendered' => $tendered,
                    'change_due' => $changeDue,
                    'status' => 'completed',
                    'processed_by' => $user->id,
                ]);

                $order->update([
                    'status' => 'completed',
                    'completed_at' => now(),
                ]);

                $table->update([
                    'status' => 'available',
                ]);

                return [
                    'order' => $order->fresh(),
                    'payment' => $payment,
                ];
            });
        } catch (HttpException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getStatusCode());
        } catch (Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not complete the payment. Please try again.',
            ], 500);
        }

        $order = $result['order'];
        $payment = $result['payment'];

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'table_id' => $order->table_id,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'completed_at' => $order->completed_at?->toIso8601String(),
                'payment' => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => (float) $payment->change_due,
                    'status' => $payment->status,
                ],
            ],
        ]);
    }
    public function index(Request $request)
    {
        if (! $request->user()->can('orders.view')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view orders',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'order_number' => 'nullable|string',
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date',
            'status' => 'nullable|in:held,new,preparing,ready,completed,cancelled',
            'payment_method' => 'nullable|in:cash,card,qr,split',
            'per_page' => 'nullable|integer|min:1|max:100',
            'page' => 'nullable|integer|min:1',
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
            $hasAccess = $user->branches()->where('branches.id', $branchId)->exists();
            if (! $hasAccess) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        }

        $perPage = (int) $request->query('per_page', 20);

        $orders = Order::query()
            // Eager-loaded up front so mapping each row in summarize()
            // below touches no additional queries (no N+1) Ã¢â‚¬â€ branch/
            // cashier/payments are exactly what the list response needs,
            // items are deliberately NOT loaded here (that's show()'s job).
            ->with(['branch:id,name,code', 'cashier:id,name', 'payments'])
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            })
            ->when($request->filled('order_number'), function ($query) use ($request) {
                $value = $request->query('order_number');
                if (is_numeric($value)) {
                    $query->where('id', (int) $value);
                } else {
                    $query->where('uuid', 'like', "%{$value}%");
                }
            })
            ->when($request->filled('date_from'), function ($query) use ($request) {
                $query->whereDate('created_at', '>=', $request->query('date_from'));
            })
            ->when($request->filled('date_to'), function ($query) use ($request) {
                $query->whereDate('created_at', '<=', $request->query('date_to'));
            })
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('status', $request->query('status'));
            })
            ->when($request->filled('payment_method'), function ($query) use ($request) {
                $query->whereHas('payments', function ($paymentQuery) use ($request) {
                    $paymentQuery->where('method', $request->query('payment_method'));
                });
            })
            ->orderByDesc('created_at')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $orders->getCollection()->map(fn (Order $order) => $this->summarize($order))->values(),
            // Additive to the existing {success, data} envelope Ã¢â‚¬â€ every
            // other endpoint's shape is unchanged.
            'meta' => [
                'current_page' => $orders->currentPage(),
                'last_page' => $orders->lastPage(),
                'per_page' => $orders->perPage(),
                'total' => $orders->total(),
            ],
        ]);
    }

    /**
     * GET /api/v1/orders/{id}
     *
     * Order::find($id) is already branch-scoped by BranchScoped Ã¢â‚¬â€ an
     * order belonging to a branch outside this user's access simply isn't
     * found, which is indistinguishable from it not existing at all. That
     * is what correctly prevents viewing another branch's order without
     * needing (or duplicating) a manual branch check here.
     */
    public function show(Request $request, int $id)
    {
        if (! $request->user()->can('orders.view')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view orders',
            ], 403);
        }

        $order = Order::query()
            ->with([
                'branch:id,name,code',
                'cashier:id,name',
                'table:id,branch_id,name,capacity,status',
                'payments',
                'items.product:id,name',
                'items.variant:id,name',
            ])
            ->find($id);

        if (! $order) {
            return response()->json([
                'success' => false,
                'message' => 'Order not found',
            ], 404);
        }

        $payment = $order->payments->first();

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'branch' => $order->branch ? [
                    'id' => $order->branch->id,
                    'name' => $order->branch->name,
                    'code' => $order->branch->code,
                ] : null,
                'cashier' => $order->cashier ? [
                    'id' => $order->cashier->id,
                    'name' => $order->cashier->name,
                ] : null,
                'table' => $order->table ? [
                    'id' => $order->table->id,
                    'name' => $order->table->name,
                    'capacity' => $order->table->capacity,
                    'status' => $order->table->status,
                ] : null,
                // Defensive against a soft-deleted/missing product or
                // variant on a historical order Ã¢â‚¬â€ never lets a null
                // relationship crash this response.
                'items' => $order->items->map(fn (OrderItem $item) => [
                    'id' => $item->id,
                    'product_id' => $item->product_id,
                    'product_variant_id' => $item->product_variant_id,
                    'product_name' => $item->product?->name ?? 'Unknown product',
                    'variant_name' => $item->variant?->name,
                    'quantity' => $item->quantity,
                    'unit_price' => (float) $item->unit_price,
                    'line_total' => round((float) $item->unit_price * $item->quantity, 2),
                ])->values(),
                'payment' => $payment ? [
                    'method' => $payment->method,
                    'status' => $payment->status,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null ? (float) $payment->tendered : null,
                    'change_due' => $payment->change_due !== null ? (float) $payment->change_due : null,
                ] : null,
                'created_at' => $order->created_at?->toIso8601String(),
            ],
        ]);
    }

    /**
     * Shared row shape for the list endpoint Ã¢â‚¬â€ deliberately lighter than
     * show()'s response (no line items), matching what the Flutter list
     * screen actually needs per row.
     */
    private function summarize(Order $order): array
    {
        $payment = $order->payments->first();

        return [
            'id' => $order->id,
            'uuid' => $order->uuid,
            'order_type' => $order->order_type,
            'status' => $order->status,
            'subtotal' => (float) $order->subtotal,
            'discount_total' => (float) $order->discount_total,
            'total' => (float) $order->total,
            'branch' => $order->branch ? [
                'id' => $order->branch->id,
                'name' => $order->branch->name,
                'code' => $order->branch->code,
            ] : null,
            'cashier' => $order->cashier ? [
                'id' => $order->cashier->id,
                'name' => $order->cashier->name,
            ] : null,
            'payment' => $payment ? [
                'method' => $payment->method,
                'status' => $payment->status,
            ] : null,
            'created_at' => $order->created_at?->toIso8601String(),
        ];
    }
}











