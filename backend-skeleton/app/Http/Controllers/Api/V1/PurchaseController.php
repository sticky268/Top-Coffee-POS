<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\Purchase;
use App\Models\PurchaseItem;
use App\Models\Supplier;
use App\Services\StockMovementService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class PurchaseController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('inventory.view')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $user = $request->user();

        $validator = Validator::make(
            $request->all(),
            [
                'branch_id' => ['nullable', 'integer', 'exists:branches,id'],
                'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $branchId = $request->input('branch_id');

        if ($branchId === null) {
            $branchId = $user->branches()
                ->orderBy('branches.id')
                ->value('branches.id');
        } else {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to this branch.',
                ], 403);
            }
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $perPage = (int) ($request->input('per_page') ?? 15);

        $purchases = Purchase::query()
            ->where('branch_id', $branchId)
            ->with([
                'supplier:id,branch_id,name,contact_name,phone,email',
                'items.ingredient:id,branch_id,unit_id,name,current_stock',
            ])
            ->orderByDesc('purchased_at')
            ->orderByDesc('id')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $purchases->items(),
            'meta' => [
                'current_page' => $purchases->currentPage(),
                'last_page' => $purchases->lastPage(),
                'per_page' => $purchases->perPage(),
                'total' => $purchases->total(),
            ],
        ]);
    }
    public function store(Request $request)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $user = $request->user();

        $validator = Validator::make(
            $request->all(),
            [
                'branch_id' => ['nullable', 'integer', 'exists:branches,id'],
                'supplier_id' => ['required', 'integer', 'exists:suppliers,id'],
                'purchased_at' => ['required', 'date'],
                'items' => ['required', 'array', 'min:1'],
                'items.*.ingredient_id' => ['required', 'integer', 'distinct', 'exists:ingredients,id'],
                'items.*.quantity' => ['required', 'numeric', 'gt:0'],
                'items.*.unit_cost' => ['required', 'numeric', 'min:0'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $branchId = $request->input('branch_id');

        if ($branchId === null) {
            $branchId = $user->branches()
                ->orderBy('branches.id')
                ->value('branches.id');
        } else {
            $canAccessBranch = $user->can('branches.view-all')
                || $user->branches()->where('branches.id', $branchId)->exists();

            if (! $canAccessBranch) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to this branch.',
                ], 403);
            }
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $supplier = Supplier::query()
            ->whereKey($request->input('supplier_id'))
            ->first();

        if (! $supplier) {
            return response()->json([
                'success' => false,
                'message' => 'Supplier not found.',
            ], 404);
        }

        if (
            $supplier->branch_id !== null
            && (int) $supplier->branch_id !== (int) $branchId
        ) {
            return response()->json([
                'success' => false,
                'message' => 'The supplier is not available for this branch.',
            ], 422);
        }

        $ingredientIds = collect($request->input('items'))
            ->pluck('ingredient_id')
            ->map(fn ($id) => (int) $id)
            ->values();

        $ingredients = Ingredient::query()
            ->whereIn('id', $ingredientIds)
            ->where('branch_id', $branchId)
            ->get()
            ->keyBy('id');

        if ($ingredients->count() !== $ingredientIds->count()) {
            return response()->json([
                'success' => false,
                'message' => 'One or more ingredients are not available for this branch.',
            ], 422);
        }

        try {
            $purchase = DB::transaction(function () use (
                $request,
                $user,
                $branchId,
                $ingredientIds,
                $ingredients,
            ) {
                $totalCost = 0.0;

                foreach ($request->input('items') as $item) {
                    $quantity = (float) $item['quantity'];
                    $unitCost = (float) $item['unit_cost'];

                    $totalCost += $quantity * $unitCost;
                }

                $purchase = Purchase::create([
                    'branch_id' => $branchId,
                    'supplier_id' => $request->input('supplier_id'),
                    'created_by' => $user->id,
                    'total_cost' => round($totalCost, 2),
                    'purchased_at' => $request->input('purchased_at'),
                ]);

                foreach ($request->input('items') as $item) {
                    $ingredient = $ingredients->get((int) $item['ingredient_id']);
                    $quantity = (float) $item['quantity'];
                    $unitCost = (float) $item['unit_cost'];

                    PurchaseItem::create([
                        'purchase_id' => $purchase->id,
                        'ingredient_id' => $ingredient->id,
                        'quantity' => $quantity,
                        'unit_cost' => $unitCost,
                    ]);

                    app(StockMovementService::class)->record(
                        $ingredient,
                        'purchase',
                        $quantity,
                        $user->id,
                        'Purchase #' . $purchase->id,
                        $purchase,
                    );
                }

                return $purchase;
            });
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }

        $purchase->load([
            'supplier:id,branch_id,name,contact_name,phone,email',
            'items.ingredient:id,branch_id,unit_id,name,current_stock',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Purchase created successfully.',
            'data' => $purchase,
        ], 201);
    }
}