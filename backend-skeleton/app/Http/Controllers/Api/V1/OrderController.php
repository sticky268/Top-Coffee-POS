<?php

namespace App\Http\Controllers\Api\V1;


use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Customer;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Services\AuditLogService;
use App\Services\OrderNumberService;
use App\Services\SaleInventoryService;
use Illuminate\Http\Request;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Throwable;

class OrderController extends Controller
{

    private function createFingerprint(Request $request, int $branchId, int $userId, string $operation): string
    {
        $data = $request->except(['uuid', 'branch_id']);
        $data['branch_id'] = $branchId;
        $data['user_id'] = $userId;
        $data['operation'] = $operation;
        $data['customer_id'] = $data['customer_id'] ?? null;
        $data['discount_total'] = round((float) ($data['discount_total'] ?? 0), 2);
        if ($operation === 'checkout') {
            $data['table_id'] = $data['table_id'] ?? null;
        }
        $sort = function ($value) use (&$sort) {
            if (! is_array($value)) {
                return $value;
            }
            if (! array_is_list($value)) {
                ksort($value);
            }
            return array_map($sort, $value);
        };
        return hash('sha256', json_encode($sort($data), JSON_THROW_ON_ERROR));
    }

    private function replayCreatedOrder(string $uuid, int $branchId, int $userId, string $fingerprint, string $operation)
    {
        $order = Order::withoutGlobalScopes()->withTrashed()->where('uuid', $uuid)->first();
        if ($order === null) {
            return null;
        }
        if ((int) $order->branch_id !== $branchId || (int) $order->user_id !== $userId
            || $order->request_fingerprint === null || ! hash_equals($order->request_fingerprint, $fingerprint)
            || $order->trashed()) {
            return response()->json(['success' => false, 'message' => 'Order UUID conflicts with an existing order.'], 409);
        }
        if ($operation === 'hold') {
            return response()->json(['success' => true, 'data' => [
                'id' => $order->id, 'order_number' => $order->order_number, 'uuid' => $order->uuid, 'order_type' => $order->order_type,
                'customer_id' => $order->customer_id, 'status' => $order->status,
                'table_id' => $order->table_id, 'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total, 'total' => (float) $order->total,
                'held_at' => $order->held_at?->toIso8601String(),
            ]], 201);
        }

        $payments = $order->payments()->get()->values();
        $payment = $payments->first();
        $isSplit = $payments->count() > 1;
        return response()->json(['success' => true, 'data' => [
            'id' => $order->id, 'order_number' => $order->order_number, 'uuid' => $order->uuid, 'order_type' => $order->order_type,
            'customer_id' => $order->customer_id, 'status' => $order->status,
            'subtotal' => (float) $order->subtotal, 'discount_total' => (float) $order->discount_total,
            'total' => (float) $order->total,
            'payment' => [
                'method' => $isSplit ? 'split' : $payment->method,
                'amount' => (float) $order->total,
                'tendered' => $isSplit || $payment->tendered === null ? null : (float) $payment->tendered,
                'change_due' => $isSplit || $payment->change_due === null ? null : (float) $payment->change_due,
            ],
            'payments' => $payments->map(fn (Payment $p) => [
                'id' => $p->id, 'method' => $p->method, 'amount' => (float) $p->amount,
                'tendered' => $p->tendered === null ? null : (float) $p->tendered,
                'change_due' => $p->change_due === null ? null : (float) $p->change_due,
                'status' => $p->status,
            ])->values()->all(),
        ]], 201);
    }

    /**
     * POST /api/v1/orders
     *
     * Creates an order + its items + its payment inside a single DB
     * transaction ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the Phase 1 architecture requirement that a payment
     * succeeding while another write fails must never leave inconsistent
     * records. Every line's price is recomputed server-side from
     * Product/ProductVariant + the resolved branch's branch_product pivot
     * (identical resolution logic to ProductController::index()) rather
     * than trusting whatever price the Flutter cart submits ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â a client
     * payload is a request, not a source of truth, for anything touching
     * payment amounts.
     *
     * Requires the 'orders.create' permission (already seeded on the
     * cashier role, and implicitly on admin via branches.view-all's
     * sibling grant of all permissions). Note: the existing manager role
     * does NOT have 'orders.create' in RolePermissionSeeder ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â a
     * pre-existing seeder gap, not introduced or fixed here.
     *
     * Deliberately NOT implemented here (out of scope for this task):
     * inventory deduction, recipes, tax calculation,
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
            'uuid' => 'nullable|uuid',
            'branch_id' => 'nullable|integer|exists:branches,id',
            'customer_id' => 'nullable|integer|exists:customers,id',
            'order_type' => 'required|in:dine_in,takeaway',
            'table_id' => 'nullable|integer|exists:restaurant_tables,id|required_if:order_type,dine_in',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.quantity' => 'required|integer|min:1',
            'discount_total' => 'nullable|numeric|min:0',
            'payment.method' => 'required|in:cash,card,qr,split',
            'payment.tendered' => 'nullable|numeric|min:0',
            'payment.payments' => 'required_if:payment.method,split|array|min:2',
            'payment.payments.*.method' => 'required|in:cash,card,qr',
            'payment.payments.*.amount' => 'required|numeric|gt:0',
            'payment.payments.*.tendered' => 'nullable|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $clientUuid = $request->input('uuid');
        $fingerprint = $clientUuid !== null
            ? $this->createFingerprint($request, (int) $branchId, (int) $user->id, 'checkout')
            : null;
        if ($clientUuid !== null) {
            $replay = $this->replayCreatedOrder($clientUuid, (int) $branchId, (int) $user->id, $fingerprint, 'checkout');
            if ($replay !== null) {
                return $replay;
            }
        }

        $customerId = $request->input('customer_id');

        if ($customerId !== null) {
            $customer = Customer::query()
                ->where('id', $customerId)
                ->where('branch_id', $branchId)
                ->first();

            if (! $customer) {
                return response()->json([
                    'success' => false,
                    'message' => 'Customer is not available at this branch.',
                ], 422);
            }
        }

        $discountTotal = round((float) $request->input('discount_total', 0), 2);
        $paymentMethod = $request->input('payment.method');
        $tendered = $request->input('payment.tendered');

        try {
            $order = DB::transaction(function () use (
                $request, $user, $branchId, $customerId, $discountTotal, $paymentMethod, $tendered, $clientUuid, $fingerprint
            ) {
                if ($request->input('order_type') === 'dine_in') {
                    $table = \App\Models\RestaurantTable::query()
                        ->where('branch_id', $branchId)
                        ->whereKey($request->input('table_id'))
                        ->lockForUpdate()
                        ->first();

                    if (! $table) {
                        abort(422, 'The selected table is not available at this branch.');
                    }

                    if (! $table->is_active) {
                        abort(422, 'The selected table is inactive.');
                    }
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
                        // Aborting here rolls back the whole transaction ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
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
                    'uuid' => $clientUuid ?? (string) Str::uuid(),
                    'request_fingerprint' => $fingerprint,
                    'branch_id' => $branchId,
                    'order_number' => app(OrderNumberService::class)->nextForBranch((int) $branchId),
                    'user_id' => $user->id,
                    'customer_id' => $customerId,
                    'order_type' => $request->input('order_type'),
                    'table_id' => $request->input('table_id'),
                    // ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â payment confirmation marks the order completed
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

                app(SaleInventoryService::class)->deductForOrder(
                    $order,
                    $user->id,
                );

                $splitPayments = $request->input('payment.payments');

                $this->createPayments(
                    $order,
                    $paymentMethod,
                    $tendered !== null ? (float) $tendered : null,
                    $splitPayments,
                    $user->id,
                );

                app(\App\Services\LoyaltyService::class)->awardForOrder($order);

                return $order->load(['items', 'payments']);
            });
        } catch (UniqueConstraintViolationException $e) {
            if ($clientUuid !== null) {
                $replay = $this->replayCreatedOrder($clientUuid, (int) $branchId, (int) $user->id, $fingerprint, 'checkout');
                if ($replay !== null) {
                    return $replay;
                }
            }
            return response()->json(['success' => false, 'message' => 'Could not resolve the order retry.'], 503);
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

        $order = $result['order'];
        $oldValues = $result['old_values'];
        $payments = $order->payments->values();

        app(AuditLogService::class)->record(
            $request,
            'order.updated',
            $order,
            $oldValues,
            [
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'items' => $order->items->map(fn (OrderItem $item) => [
                    'product_id' => $item->product_id,
                    'product_variant_id' => $item->product_variant_id,
                    'quantity' => (int) $item->quantity,
                    'unit_price' => (float) $item->unit_price,
                ])->values()->all(),
            ],
        );

        $payment = $payments->first();
        $isSplit = $payments->count() > 1;

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
                'status' => $order->status,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'payment' => [
                    'method' => $isSplit ? 'split' : $payment->method,
                    'amount' => (float) $order->total,
                    'tendered' => $isSplit || $payment->tendered === null
                        ? null
                        : (float) $payment->tendered,
                    'change_due' => $isSplit || $payment->change_due === null
                        ? null
                        : (float) $payment->change_due,
                ],
                'payments' => $payments->map(fn (Payment $payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => $payment->change_due !== null
                        ? (float) $payment->change_due
                        : null,
                    'status' => $payment->status,
                ])->values()->all(),
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
     *     leaves it unrestricted for branches.view-all holders) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â this
     *     alone already makes it impossible for a user to see another
     *     branch's orders, with or without the parameter below.
     *  2. The new `branch_id` param ADDITIONALLY narrows within that
     *     already-safe set, to a single branch ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â this is what lets a
     *     multi-branch user (e.g. an admin switching branches in the
     *     Flutter app) scope the list to just the branch they're
     *     currently viewing, rather than always seeing every branch they
     *     have access to at once. An explicit 403 (matching Category/
     *     Product/Order-create's existing convention) is returned for a
     *     branch_id the user doesn't have access to, rather than
     *     silently returning zero rows ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â that ambiguity (no access vs.
     *     genuinely empty) is worse for a UI to interpret correctly.
     *
     * "order_number" matches this app's existing convention (see
     * OrderController::store()'s response and the Flutter checkout
     * confirmation screen) of using the numeric `id` as the user-facing
     * order number ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â there is no separate order_number column. A numeric
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
            'uuid' => 'nullable|uuid',
            'branch_id' => 'nullable|integer|exists:branches,id',
            'customer_id' => 'nullable|integer|exists:customers,id',
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

        $clientUuid = $request->input('uuid');
        $fingerprint = $clientUuid !== null
            ? $this->createFingerprint($request, (int) $branchId, (int) $user->id, 'hold')
            : null;
        if ($clientUuid !== null) {
            $replay = $this->replayCreatedOrder($clientUuid, (int) $branchId, (int) $user->id, $fingerprint, 'hold');
            if ($replay !== null) {
                return $replay;
            }
        }

        try {
            $order = DB::transaction(function () use ($request, $user, $branchId, $clientUuid, $fingerprint) {
                $table = \App\Models\RestaurantTable::query()
                    ->where('branch_id', $branchId)
                    ->where('id', $request->input('table_id'))
                    ->lockForUpdate()
                    ->first();

                if (! $table) {
                    abort(422, 'The selected table is not available at this branch.');
                }

                if (! $table->is_active) {
                    abort(422, 'The selected table is inactive.');
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

                $customerId = $request->input('customer_id');

        if ($customerId !== null) {
            $customer = Customer::query()
                ->where('id', $customerId)
                ->where('branch_id', $branchId)
                ->first();

            if (! $customer) {
                abort(422, 'Customer is not available at this branch.');
            }
        }

        $discountTotal = round((float) $request->input('discount_total', 0), 2);
                $total = max(0, round($subtotal - $discountTotal, 2));

                $order = Order::create([
                    'uuid' => $clientUuid ?? (string) Str::uuid(),
                    'request_fingerprint' => $fingerprint,
                    'branch_id' => $branchId,
                    'order_number' => app(OrderNumberService::class)->nextForBranch((int) $branchId),
                    'user_id' => $user->id,
                    'customer_id' => $customerId,
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

                app(AuditLogService::class)->record(
                    $request,
                    'order.held',
                    $order,
                    null,
                    [
                        'branch_id' => $order->branch_id,
                        'table_id' => $order->table_id,
                        'customer_id' => $order->customer_id,
                        'status' => $order->status,
                        'subtotal' => (float) $order->subtotal,
                        'discount_total' => (float) $order->discount_total,
                        'total' => (float) $order->total,
                    ],
                );

                return $order->load(['items']);
            });
        } catch (UniqueConstraintViolationException $e) {
            if ($clientUuid !== null) {
                $replay = $this->replayCreatedOrder($clientUuid, (int) $branchId, (int) $user->id, $fingerprint, 'hold');
                if ($replay !== null) {
                    return $replay;
                }
            }
            return response()->json(['success' => false, 'message' => 'Could not resolve the order retry.'], 503);
        } catch (HttpException $e) {
            // A concurrent hold may occupy the table before this request obtains
            // its lock. If it was the same UUID, return the original order.
            if ($clientUuid !== null) {
                $replay = $this->replayCreatedOrder($clientUuid, (int) $branchId, (int) $user->id, $fingerprint, 'hold');
                if ($replay !== null) {
                    return $replay;
                }
            }
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
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
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
            $result = DB::transaction(function () use ($request, $user, $id) {
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

                $customerId = $request->input('customer_id', $order->customer_id);

        if ($customerId !== null) {
            $customer = Customer::query()
                ->where('id', $customerId)
                ->where('branch_id', $order->branch_id)
                ->first();

            if (! $customer) {
                abort(422, 'Customer is not available at this branch.');
            }
        }

        $discountTotal = round((float) $request->input('discount_total', 0), 2);
                $total = max(0, round($subtotal - $discountTotal, 2));

                $oldValues = [
                    'subtotal' => (float) $order->subtotal,
                    'discount_total' => (float) $order->discount_total,
                    'total' => (float) $order->total,
                    'status' => $order->status,
                    'branch_id' => $order->branch_id,
                    'table_id' => $order->table_id,
                ];

                $order->update([
                    'subtotal' => round($subtotal, 2),
                    'discount_total' => $discountTotal,
                    'tax_total' => 0,
                    'total' => $total,
                    'held_at' => $order->held_at ?? now(),
                    'customer_id' => $customerId,
                ]);

                // Held orders remain freely editable until payment. Replace the
                // active bill with the cashier's latest item list.
                $order->items()->delete();
                foreach ($resolvedItems as $item) {
                    OrderItem::create(array_merge($item, ['order_id' => $order->id]));
                }

                if ($table->status !== 'occupied') {
                    $table->update([
                        'status' => 'occupied',
                    ]);
                }

                return [
                    'order' => $order->load(['items']),
                    'old_values' => $oldValues,
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
                'message' => 'Could not update the order. Please try again.',
            ], 500);
        }

        $order = $result['order'];
        $oldValues = $result['old_values'];

        app(AuditLogService::class)->record(
            $request,
            'order.updated',
            $order,
            $oldValues,
            [
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'status' => $order->status,
                'branch_id' => $order->branch_id,
                'table_id' => $order->table_id,
            ],
        );

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
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
     * POST /api/v1/orders/{id}/cancel
     * Cancel an unpaid held dine-in order without deleting its history.
     */
    public function cancelHeld(Request $request, int $id)
    {
        if (! $request->user()->can('orders.cancel')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to cancel orders',
            ], 403);
        }

        $user = $request->user();

        try {
            $order = DB::transaction(function () use ($user, $id) {
                $order = Order::query()
                    ->whereKey($id)
                    ->lockForUpdate()
                    ->first();

                if (! $order) {
                    abort(404, 'Order not found.');
                }

                if (! $user->can('branches.view-all')
                    && ! $user->branches()->where('branches.id', $order->branch_id)->exists()) {
                    abort(403, 'You do not have access to this branch.');
                }

                if ($order->status !== 'held' || $order->order_type !== 'dine_in') {
                    abort(409, 'Only held dine-in orders can be cancelled.');
                }

                if ($order->payments()->exists()) {
                    abort(409, 'An order with payments cannot be cancelled.');
                }

                $table = \App\Models\RestaurantTable::query()
                    ->where('branch_id', $order->branch_id)
                    ->whereKey($order->table_id)
                    ->lockForUpdate()
                    ->first();

                $order->update(['status' => 'cancelled']);

                if ($table) {
                    $otherHeldOrders = Order::query()
                        ->where('branch_id', $order->branch_id)
                        ->where('table_id', $table->id)
                        ->where('status', 'held')
                        ->exists();

                    if (! $otherHeldOrders) {
                        $table->update(['status' => 'available']);
                    }
                }

                return $order->fresh();
            });
        } catch (HttpException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getStatusCode());
        } catch (Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not cancel the order. Please try again.',
            ], 500);
        }

        app(AuditLogService::class)->record(
            $request,
            'order.cancelled',
            $order,
            ['status' => 'held', 'branch_id' => $order->branch_id, 'table_id' => $order->table_id],
            ['status' => 'cancelled', 'branch_id' => $order->branch_id, 'table_id' => $order->table_id],
        );

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'status' => $order->status,
                'table_id' => $order->table_id,
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
            'expected_total' => 'nullable|numeric|min:0',
            'payment.method' => 'required|in:cash,card,qr,split',
            'payment.tendered' => 'nullable|numeric|min:0',
            'payment.payments' => 'required_if:payment.method,split|array|min:2',
            'payment.payments.*.method' => 'required|in:cash,card,qr',
            'payment.payments.*.amount' => 'required|numeric|gt:0',
            'payment.payments.*.tendered' => 'nullable|numeric|min:0',
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

                if ($request->filled('expected_total')
                    && (int) round((float) $request->input('expected_total') * 100)
                        !== (int) round((float) $order->total * 100)) {
                    abort(409, 'The order total has changed. Review the saved bill before paying.');
                }

                $splitPayments = $request->input('payment.payments');

                app(SaleInventoryService::class)->deductForOrder(
                    $order,
                    $user->id,
                );

                $payments = $this->createPayments(
                    $order,
                    $paymentMethod,
                    $tenderedInput !== null ? (float) $tenderedInput : null,
                    $splitPayments,
                    $user->id,
                    true,
                );
                $order->update([
                    'status' => 'completed',
                    'completed_at' => now(),
                ]);

                $table->update([
                    'status' => 'available',
                ]);

                return [
                    'order' => $order->fresh(),
                    'payments' => $payments,
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
        $payments = collect($result['payments'])->values();

        app(\App\Services\LoyaltyService::class)->awardForOrder($order);

        app(AuditLogService::class)->record(
            $request,
            'order.paid',
            $order,
            [
                'status' => 'held',
                'branch_id' => $order->branch_id,
                'table_id' => $order->table_id,
                'customer_id' => $order->customer_id,
                'total' => (float) $order->total,
            ],
            [
                'status' => 'completed',
                'branch_id' => $order->branch_id,
                'table_id' => $order->table_id,
                'customer_id' => $order->customer_id,
                'total' => (float) $order->total,
                'payments' => $payments->map(fn (Payment $payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => $payment->change_due !== null
                        ? (float) $payment->change_due
                        : null,
                    'status' => $payment->status,
                ])->values()->all(),
            ],
        );
        $payment = $payments->first();
        $isSplit = $payments->count() > 1;

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
                'status' => $order->status,
                'table_id' => $order->table_id,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'completed_at' => $order->completed_at?->toIso8601String(),
                'payment' => [
                    'id' => $isSplit ? null : $payment->id,
                    'method' => $isSplit ? 'split' : $payment->method,
                    'amount' => (float) $order->total,
                    'tendered' => $isSplit || $payment->tendered === null
                        ? null
                        : (float) $payment->tendered,
                    'change_due' => $isSplit || $payment->change_due === null
                        ? null
                        : (float) $payment->change_due,
                    'status' => $isSplit ? 'completed' : $payment->status,
                ],
                'payments' => $payments->map(fn (Payment $payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => $payment->change_due !== null
                        ? (float) $payment->change_due
                        : null,
                    'status' => $payment->status,
                ])->values()->all(),
            ],
        ]);
    }
    private function createPayments(
        Order $order,
        string $paymentMethod,
        ?float $tendered,
        ?array $splitPayments,
        int $processedBy,
        bool $heldPayment = false,
    ): array {
        $total = round((float) $order->total, 2);

        if ($paymentMethod !== 'split') {
            $changeDue = null;

            if ($paymentMethod === 'cash') {
                if ($heldPayment && $tendered === null) {
                    $tendered = $total;
                }

                if ($tendered !== null) {
                    $tendered = round($tendered, 2);
                    $changeDue = round($tendered - $total, 2);

                    if ($tendered < $total) {
                        abort(422, 'Cash tendered is less than the order total.');
                    }
                }
            } else {
                $tendered = null;
                $changeDue = $heldPayment ? 0 : null;
            }

            return [
                Payment::create([
                    'order_id' => $order->id,
                    'method' => $paymentMethod,
                    'amount' => $total,
                    'tendered' => $paymentMethod === 'cash' ? $tendered : null,
                    'change_due' => $changeDue,
                    'status' => 'completed',
                    'processed_by' => $processedBy,
                ]),
            ];
        }

        $payments = $splitPayments ?? [];

        if (count($payments) < 2) {
            abort(422, 'A split payment must contain at least two payment methods.');
        }

        $splitTotal = round(
            collect($payments)->sum(
                fn (array $payment) => (float) $payment['amount']
            ),
            2
        );

        if (abs($splitTotal - $total) > 0.001) {
            abort(422, 'Split payment amounts must equal the order total.');
        }

        $createdPayments = [];

        foreach ($payments as $paymentInput) {
            $method = $paymentInput['method'];
            $amount = round((float) $paymentInput['amount'], 2);
            $portionTendered = $paymentInput['tendered'] ?? null;
            $changeDue = null;

            if ($method === 'cash') {
                if ($portionTendered === null) {
                    abort(422, 'Cash split payment requires a tendered amount.');
                }

                $portionTendered = round((float) $portionTendered, 2);

                if ($portionTendered < $amount) {
                    abort(422, 'Cash tendered is less than the split payment amount.');
                }

                $changeDue = round($portionTendered - $amount, 2);
            } else {
                $portionTendered = null;
            }

            $createdPayments[] = Payment::create([
                'order_id' => $order->id,
                'method' => $method,
                'amount' => $amount,
                'tendered' => $portionTendered,
                'change_due' => $changeDue,
                'status' => 'completed',
                'processed_by' => $processedBy,
            ]);
        }

        return $createdPayments;
    }
    /**
     * PATCH /api/v1/orders/{id}
     *
     * Edit a completed historical order.
     *
     * Existing payment records are preserved. Because payment reconciliation
     * is not performed by this endpoint, the edited total must remain equal
     * to the amount already paid.
     */
    public function update(Request $request, int $id)
    {
        if (! $request->user()->can('orders.edit')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to edit orders',
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
                    ->withoutGlobalScope('branch')
                    ->where('id', $id)
                    ->where('status', 'completed')
                    ->lockForUpdate()
                    ->first();

                if (! $order) {
                    abort(404, 'Completed order not found.');
                }

                if (! $user->can('branches.view-all')
                    && ! $user->branches()->where('branches.id', $order->branch_id)->exists()) {
                    abort(403, 'You do not have access to this branch.');
                }

                $order->load([
                    'items',
                    'payments' => function ($query) {
                        $query->where('status', 'completed');
                    },
                ]);

                $paidTotal = round(
                    $order->payments->sum(
                        fn (Payment $payment) => (float) $payment->amount
                    ),
                    2
                );

                $oldValues = [
                    'subtotal' => (float) $order->subtotal,
                    'discount_total' => (float) $order->discount_total,
                    'total' => (float) $order->total,
                    'items' => $order->items->map(fn (OrderItem $item) => [
                        'product_id' => $item->product_id,
                        'product_variant_id' => $item->product_variant_id,
                        'quantity' => (int) $item->quantity,
                        'unit_price' => (float) $item->unit_price,
                    ])->values()->all(),
                ];

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
                        abort(
                            422,
                            "Product {$itemInput['product_id']} is not available at this branch."
                        );
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
                            abort(
                                422,
                                "Variant {$variantId} is not valid for product {$product->id}."
                            );
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

                $discountTotal = round(
                    (float) $request->input(
                        'discount_total',
                        $order->discount_total ?? 0
                    ),
                    2
                );

                $total = max(
                    0,
                    round($subtotal - $discountTotal, 2)
                );

                if (abs($total - $paidTotal) > 0.009) {
                    abort(
                        422,
                        'A completed order adjustment cannot change the amount already paid. Use the refund or additional payment workflow for payment changes.'
                    );
                }

                app(SaleInventoryService::class)->reverseForOrder(
                    $order,
                    $user->id,
                );

                $order->items()->delete();

                foreach ($resolvedItems as $item) {
                    OrderItem::create(array_merge($item, [
                        'order_id' => $order->id,
                    ]));
                }

                $order->update([
                    'subtotal' => round($subtotal, 2),
                    'discount_total' => $discountTotal,
                    'tax_total' => 0,
                    'total' => $total,
                ]);

                app(SaleInventoryService::class)->deductForOrder(
                    $order->fresh(),
                    $user->id,
                );

                return [
                    'order' => $order->fresh()->load([
                        'items',
                        'payments',
                    ]),
                    'old_values' => $oldValues,
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
                'message' => 'Could not update the order. Please try again.',
            ], 500);
        }

        $payments = $order->payments->values();

        app(AuditLogService::class)->record(
            $request,
            'order.created',
            $order,
            null,
            [
                'branch_id' => $order->branch_id,
                'customer_id' => $order->customer_id,
                'order_type' => $order->order_type,
                'status' => $order->status,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
            ],
        );

        app(AuditLogService::class)->record(
            $request,
            'order.paid',
            $order,
            [
                'status' => 'held',
                'branch_id' => $order->branch_id,
                'table_id' => $order->table_id,
                'customer_id' => $order->customer_id,
                'total' => (float) $order->total,
            ],
            [
                'status' => 'completed',
                'branch_id' => $order->branch_id,
                'table_id' => $order->table_id,
                'customer_id' => $order->customer_id,
                'total' => (float) $order->total,
                'payments' => $payments->map(fn (Payment $payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => $payment->change_due !== null
                        ? (float) $payment->change_due
                        : null,
                    'status' => $payment->status,
                ])->values()->all(),
            ],
        );

        $payment = $payments->first();
        $isSplit = $payments->count() > 1;

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $order->id,
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
                'status' => $order->status,
                'subtotal' => (float) $order->subtotal,
                'discount_total' => (float) $order->discount_total,
                'total' => (float) $order->total,
                'payment' => $payment ? [
                    'method' => $isSplit ? 'split' : $payment->method,
                    'amount' => (float) $order->total,
                    'tendered' => $isSplit || $payment->tendered === null
                        ? null
                        : (float) $payment->tendered,
                    'change_due' => $isSplit || $payment->change_due === null
                        ? null
                        : (float) $payment->change_due,
                    'status' => $payment->status,
                ] : null,
                'payments' => $payments->map(fn (Payment $payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null
                        ? (float) $payment->tendered
                        : null,
                    'change_due' => $payment->change_due !== null
                        ? (float) $payment->change_due
                        : null,
                    'status' => $payment->status,
                ])->values()->all(),
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
            'customer_id' => 'nullable|integer|exists:customers,id',
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
            // below touches no additional queries (no N+1) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â branch/
            // cashier/payments are exactly what the list response needs,
            // items are deliberately NOT loaded here (that's show()'s job).
            ->with(['branch:id,name,code', 'cashier:id,name', 'payments'])
            ->when($branchId !== null, function ($query) use ($branchId) {
                $query->where('branch_id', $branchId);
            })
            ->when($request->filled('order_number'), function ($query) use ($request) {
                $value = $request->query('order_number');
                if (is_numeric($value)) {
                    $query->where('order_number', (int) $value);
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
                $paymentMethod = $request->query('payment_method');

                if ($paymentMethod === 'split') {
                    $query->whereHas('payments', function ($paymentQuery) {
                        $paymentQuery->where('status', 'completed');
                    })->has('payments', '>=', 2);
                } else {
                    $query->whereHas('payments', function ($paymentQuery) use ($paymentMethod) {
                        $paymentQuery->where('method', $paymentMethod);
                    });
                }
            })
            ->orderByDesc('created_at')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $orders->getCollection()->map(fn (Order $order) => $this->summarize($order))->values(),
            // Additive to the existing {success, data} envelope ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â every
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
     * Order::find($id) is already branch-scoped by BranchScoped ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â an
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
                'order_number' => $order->order_number,
                'uuid' => $order->uuid,
                'order_type' => $order->order_type,
                'customer_id' => $order->customer_id,
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
                // variant on a historical order ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never lets a null
                // relationship crash this response.
                'items' => $order->items->where('quantity', '>', 0)->map(fn (OrderItem $item) => [
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
                'payments' => $order->payments->map(fn ($payment) => [
                    'id' => $payment->id,
                    'method' => $payment->method,
                    'status' => $payment->status,
                    'amount' => (float) $payment->amount,
                    'tendered' => $payment->tendered !== null ? (float) $payment->tendered : null,
                    'change_due' => $payment->change_due !== null ? (float) $payment->change_due : null,
                ])->values(),
                'created_at' => $order->created_at?->toIso8601String(),
            ],
        ]);
    }

    /**
     * Shared row shape for the list endpoint ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â deliberately lighter than
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











