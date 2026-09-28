<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Expense;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ExpenseController extends Controller
{
    /**
     * GET /api/v1/expenses
     *
     * Returns expenses for the selected branch.
     */
    public function index(Request $request)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $validator = Validator::make($request->all(), [
            'category_id' => 'nullable|integer|exists:expense_categories,id',
            'date_from' => 'nullable|date',
            'date_to' => 'nullable|date',
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

        $query = Expense::query()
            ->with([
                'category:id,name',
                'user:id,name,email',
                'branch:id,name',
            ])
            ->where('branch_id', $branchId);

        if ($request->filled('category_id')) {
            $query->where(
                'expense_category_id',
                $request->integer('category_id')
            );
        }

        if ($request->filled('date_from')) {
            $query->whereDate('spent_at', '>=', $request->input('date_from'));
        }

        if ($request->filled('date_to')) {
            $query->whereDate('spent_at', '<=', $request->input('date_to'));
        }

        if ($request->filled('search')) {
            $search = $request->input('search');

            $query->where('description', 'like', '%' . $search . '%');
        }

        $perPage = $request->integer('per_page', 20);

        $expenses = $query
            ->orderByDesc('spent_at')
            ->orderByDesc('id')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $expenses->items(),
            'meta' => [
                'current_page' => $expenses->currentPage(),
                'last_page' => $expenses->lastPage(),
                'per_page' => $expenses->perPage(),
                'total' => $expenses->total(),
            ],
        ]);
    }

    /**
     * Resolve the requested branch while enforcing branch access.
     */
    /**
     * POST /api/v1/expenses
     *
     * Creates a new expense for the selected branch.
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $validator = Validator::make($request->all(), [
            'category_id' => 'required|integer|exists:expense_categories,id',
            'amount' => 'required|numeric|min:0.01',
            'description' => 'nullable|string|max:255',
            'spent_at' => 'required|date',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $expense = Expense::create([
            'branch_id' => $branchId,
            'expense_category_id' => $request->integer('category_id'),
            'user_id' => $request->user()->id,
            'amount' => $request->input('amount'),
            'description' => $request->input('description'),
            'spent_at' => $request->input('spent_at'),
        ]);

        $expense->load([
            'category:id,name',
            'user:id,name,email',
            'branch:id,name',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Expense created successfully',
            'data' => $expense,
        ], 201);
    }
    /**
     * GET /api/v1/expenses/summary
     *
     * Returns expense dashboard totals, trend, and category breakdown
     * for the selected branch.
     */
    public function summary(Request $request)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $today = now()->startOfDay();
        $tomorrow = $today->copy()->addDay();

        $weekStart = now()->startOfWeek();
        $nextWeekStart = $weekStart->copy()->addWeek();
        $previousWeekStart = $weekStart->copy()->subWeek();

        $monthStart = now()->startOfMonth();
        $nextMonthStart = $monthStart->copy()->addMonth();
        $previousMonthStart = $monthStart->copy()->subMonth();

        $baseQuery = Expense::query()
            ->where('branch_id', $branchId);

        $todayTotal = (clone $baseQuery)
            ->whereDate('spent_at', $today)
            ->sum('amount');

        $weekTotal = (clone $baseQuery)
            ->where('spent_at', '>=', $weekStart->toDateString())
            ->where('spent_at', '<', $nextWeekStart->toDateString())
            ->sum('amount');

        $previousWeekTotal = (clone $baseQuery)
            ->where('spent_at', '>=', $previousWeekStart->toDateString())
            ->where('spent_at', '<', $weekStart->toDateString())
            ->sum('amount');

        $monthTotal = (clone $baseQuery)
            ->where('spent_at', '>=', $monthStart->toDateString())
            ->where('spent_at', '<', $nextMonthStart->toDateString())
            ->sum('amount');

        $previousMonthTotal = (clone $baseQuery)
            ->where('spent_at', '>=', $previousMonthStart->toDateString())
            ->where('spent_at', '<', $monthStart->toDateString())
            ->sum('amount');

        $trendStart = $today->copy()->subDays(6);

        $trendRows = (clone $baseQuery)
            ->selectRaw('spent_at, SUM(amount) as total')
            ->where('spent_at', '>=', $trendStart->toDateString())
            ->where('spent_at', '<', $tomorrow->toDateString())
            ->groupBy('spent_at')
            ->orderBy('spent_at')
            ->get();

        $trendMap = $trendRows->mapWithKeys(function ($row) {
            return [
                $row->spent_at->toDateString() => (float) $row->total,
            ];
        });

        $trend = collect();

        for ($date = $trendStart->copy(); $date->lte($today); $date->addDay()) {
            $dateKey = $date->toDateString();

            $trend->push([
                'date' => $dateKey,
                'day' => $date->format('D'),
                'amount' => $trendMap[$dateKey] ?? 0.0,
            ]);
        }

        $categoryRows = (clone $baseQuery)
            ->selectRaw(
                'expense_category_id, SUM(amount) as total'
            )
            ->with('category:id,name')
            ->where('spent_at', '>=', $monthStart->toDateString())
            ->where('spent_at', '<', $nextMonthStart->toDateString())
            ->groupBy('expense_category_id')
            ->orderByDesc('total')
            ->get();

        $categories = $categoryRows->map(function ($row) {
            return [
                'category_id' => $row->expense_category_id,
                'category_name' => $row->category?->name ?? 'Unknown',
                'amount' => (float) $row->total,
            ];
        })->values();

        return response()->json([
            'success' => true,
            'data' => [
                'today' => (float) $todayTotal,
                'week' => (float) $weekTotal,
                'previous_week' => (float) $previousWeekTotal,
                'month' => (float) $monthTotal,
                'previous_month' => (float) $previousMonthTotal,
                'trend' => $trend,
                'categories' => $categories,
            ],
        ]);
    }
    /**
     * GET /api/v1/expenses/{id}
     *
     * Returns one expense for the selected branch.
     */
    public function show(Request $request, $id)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $expense = Expense::query()
            ->with([
                'category:id,name',
                'user:id,name,email',
                'branch:id,name',
            ])
            ->where('branch_id', $branchId)
            ->find($id);

        if (! $expense) {
            return response()->json([
                'success' => false,
                'message' => 'Expense not found',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $expense,
        ]);
    }
    /**
     * PATCH /api/v1/expenses/{id}
     *
     * Updates an existing expense.
     */
    public function update(Request $request, $id)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $expense = Expense::query()
            ->where('branch_id', $branchId)
            ->find($id);

        if (! $expense) {
            return response()->json([
                'success' => false,
                'message' => 'Expense not found',
            ], 404);
        }

        $validator = Validator::make($request->all(), [
            'category_id' => 'sometimes|required|integer|exists:expense_categories,id',
            'amount' => 'sometimes|required|numeric|min:0.01',
            'description' => 'sometimes|nullable|string|max:255',
            'spent_at' => 'sometimes|required|date',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $updates = [];

        if ($request->has('category_id')) {
            $updates['expense_category_id'] = $request->integer('category_id');
        }

        if ($request->has('amount')) {
            $updates['amount'] = $request->input('amount');
        }

        if ($request->has('description')) {
            $updates['description'] = $request->input('description');
        }

        if ($request->has('spent_at')) {
            $updates['spent_at'] = $request->input('spent_at');
        }

        $expense->update($updates);

        $expense->load([
            'category:id,name',
            'user:id,name,email',
            'branch:id,name',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Expense updated successfully',
            'data' => $expense,
        ]);
    }
    /**
     * DELETE /api/v1/expenses/{id}
     *
     * Soft deletes an expense for the selected branch.
     */
    public function destroy(Request $request, $id)
    {
        if (! $request->user()->can('expenses.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage expenses',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $expense = Expense::query()
            ->where('branch_id', $branchId)
            ->find($id);

        if (! $expense) {
            return response()->json([
                'success' => false,
                'message' => 'Expense not found',
            ], 404);
        }

        $expense->delete();

        return response()->json([
            'success' => true,
            'message' => 'Expense deleted successfully',
        ]);
    }
    private function resolveBranchId(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
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
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }

            return (int) $branchId;
        }

        $branch = $user->branches()->wherePivot('is_primary', true)->first()
            ?? $user->branches()->first();

        if (! $branch) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is assigned to this user',
            ], 422);
        }

        return (int) $branch->id;
    }
}
