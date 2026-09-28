<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\DB;

class CustomerController extends Controller
{
    /**
     * GET /api/v1/customers
     *
     * Returns customers visible to the selected branch:
     * global customers (branch_id IS NULL) plus customers
     * belonging to that branch.
     */
    public function index(Request $request)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'search' => 'nullable|string|max:255',
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

        if ($branchId !== null) {
            $branchId = (int) $branchId;

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

        $query = Customer::query()
            ->where(function ($query) use ($branchId) {
                $query->whereNull('branch_id')
                    ->orWhere('branch_id', $branchId);
            });

        if ($request->filled('search')) {
            $search = trim($request->input('search'));

            $query->where(function ($query) use ($search) {
                $query->where('name', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%");
            });
        }

        $perPage = (int) $request->input('per_page', 20);

        $customers = $query
            ->withCount([
                'orders as completed_orders_count' => function ($query) {
                    $query->where('status', 'completed');
                },
            ])
            ->withSum([
                'orders as completed_orders_total' => function ($query) {
                    $query->where('status', 'completed');
                },
            ], 'total')
            ->orderBy('name')
            ->orderBy('id')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $customers->items(),
            'meta' => [
                'current_page' => $customers->currentPage(),
                'last_page' => $customers->lastPage(),
                'per_page' => $customers->perPage(),
                'total' => $customers->total(),
            ],
        ]);
    }

    /**
     * POST /api/v1/customers
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'notes' => 'nullable|string',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        $branchId = $request->input('branch_id');

        if ($branchId !== null) {
            $branchId = (int) $branchId;

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

        $customer = Customer::create([
            'branch_id' => $branchId,
            'name' => trim($request->input('name')),
            'phone' => $request->input('phone'),
            'email' => $request->input('email'),
            'notes' => $request->input('notes'),
        ]);

        return response()->json([
            'success' => true,
            'data' => $customer,
        ], 201);
    }

    /**
     * GET /api/v1/customers/{customer}
     */
    public function show(Request $request, Customer $customer)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        $customer->loadCount([
            'orders as completed_orders_count' => function ($query) {
                $query->where('status', 'completed');
            },
        ]);

        $customer->loadSum([
            'orders as completed_orders_total' => function ($query) {
                $query->where('status', 'completed');
            },
        ], 'total');

        $customer->load([
            'orders' => function ($query) {
                $query->where('status', 'completed')
                    ->with(['items.product'])
                    ->latest('created_at');
            },
        ]);

        return response()->json([
            'success' => true,
            'data' => $customer,
        ]);
    }

    /**
     * PATCH /api/v1/customers/{customer}
     */
    public function update(Request $request, Customer $customer)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        if ($customer->branch_id === null) {
            return response()->json([
                'success' => false,
                'message' => 'Global customers cannot be modified',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'phone' => 'sometimes|nullable|string|max:50',
            'email' => 'sometimes|nullable|email|max:255',
            'notes' => 'sometimes|nullable|string',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $customer->fill($request->only([
            'name',
            'phone',
            'email',
            'notes',
        ]));

        if ($request->has('name')) {
            $customer->name = trim($request->input('name'));
        }

        $customer->save();

        return response()->json([
            'success' => true,
            'data' => $customer->fresh(),
        ]);
    }

    /**
     * DELETE /api/v1/customers/{customer}
     *
     * Soft deletes the customer. Existing orders remain intact.
     */
    public function destroy(Request $request, Customer $customer)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        if ($customer->branch_id === null) {
            return response()->json([
                'success' => false,
                'message' => 'Global customers cannot be deactivated',
            ], 403);
        }

        $customer->delete();

        return response()->json([
            'success' => true,
            'message' => 'Customer deactivated successfully',
        ]);
    }

    /**
     * GET /api/v1/customers/{customer}/orders
     */
    public function orders(Request $request, Customer $customer)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        $orders = $customer->orders()
            ->where('status', 'completed')
            ->with(['items.product', 'payments'])
            ->latest('created_at')
            ->paginate((int) $request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => $orders->items(),
            'meta' => [
                'current_page' => $orders->currentPage(),
                'last_page' => $orders->lastPage(),
                'per_page' => $orders->perPage(),
                'total' => $orders->total(),
            ],
        ]);
    }
    /**
     * GET /api/v1/customers/{customer}/loyalty
     */
    public function loyalty(Request $request, Customer $customer)
    {
        if (! $request->user()->can('customers.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage customers',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        $account = $customer->loyaltyAccount()->first();

        if (! $account) {
            $account = $customer->loyaltyAccount()->create([
                'points_balance' => 0,
                'lifetime_earned' => 0,
                'lifetime_redeemed' => 0,
            ]);
        }

        $transactions = $account->transactions()
            ->with(['branch:id,name', 'order:id,uuid'])
            ->latest('created_at')
            ->paginate((int) $request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => [
                'customer' => $customer,
                'account' => $account,
                'transactions' => $transactions->items(),
                'meta' => [
                    'current_page' => $transactions->currentPage(),
                    'last_page' => $transactions->lastPage(),
                    'per_page' => $transactions->perPage(),
                    'total' => $transactions->total(),
                ],
            ],
        ]);
    }
        /**
     * POST /api/v1/customers/{customer}/loyalty/adjust
     */
    public function adjustLoyalty(Request $request, Customer $customer)
    {
        if (! $request->user()->can('loyalty.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage loyalty',
            ], 403);
        }

        if (! $this->customerIsAccessible($request, $customer)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this customer',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'points' => 'required|integer|not_in:0',
            'description' => 'nullable|string|max:255',
            'branch_id' => 'nullable|integer|exists:branches,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $validated = $validator->validated();
        $user = $request->user();

        $branchId = $validated['branch_id'] ?? null;

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

        $result = DB::transaction(function () use ($customer, $validated, $branchId) {
            $account = $customer->loyaltyAccount()->first();

            if (! $account) {
                $account = $customer->loyaltyAccount()->create([
                    'points_balance' => 0,
                    'lifetime_earned' => 0,
                    'lifetime_redeemed' => 0,
                ]);
            }

            $account = $customer->loyaltyAccount()
                ->lockForUpdate()
                ->first();

            $points = (int) $validated['points'];
            $newBalance = $account->points_balance + $points;

            if ($newBalance < 0) {
                return [
                    'error' => 'Loyalty points balance cannot be negative.',
                ];
            }

            $account->update([
                'points_balance' => $newBalance,
            ]);

            $transaction = $account->transactions()->create([
                'customer_id' => $customer->id,
                'branch_id' => $branchId,
                'order_id' => null,
                'type' => 'adjustment',
                'points' => $points,
                'balance_after' => $newBalance,
                'description' => $validated['description'] ?? null,
            ]);

            return [
                'account' => $account->fresh(),
                'transaction' => $transaction,
            ];
        });

        if (isset($result['error'])) {
            return response()->json([
                'success' => false,
                'message' => $result['error'],
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'Loyalty points adjusted successfully',
            'data' => $result,
        ]);
    }
/**
     * Determines whether the authenticated user can access the customer.
     */private function customerIsAccessible(Request $request, Customer $customer): bool
    {
        if ($customer->branch_id === null) {
            return true;
        }

        $user = $request->user();

        return $user->can('branches.view-all')
            || $user->branches()->where('branches.id', $customer->branch_id)->exists();
    }
}
