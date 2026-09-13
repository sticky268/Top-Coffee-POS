<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\RestaurantTable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

class RestaurantTableController extends Controller
{
    /**
     * GET /api/v1/tables
     *
     * Returns all tables for the selected branch.
     */
    public function index(Request $request)
    {
        if (! $request->user()->can('tables.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to view tables',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $tables = RestaurantTable::query()
            ->where('branch_id', $branchId)
            ->addSelect([
                'active_order_id' => Order::query()
                    ->select('id')
                    ->whereColumn('table_id', 'restaurant_tables.id')
                    ->where('status', 'held')
                    ->latest('id')
                    ->limit(1),
            ])
            ->orderBy('name')
            ->get([
                'id',
                'branch_id',
                'name',
                'capacity',
                'status',
                'section',
                'shape',
                'color',
                'is_active',
            ]);

        return response()->json([
            'success' => true,
            'data' => $tables,
        ]);
    }

    /**
     * POST /api/v1/tables
     *
     * Creates a new table for the selected branch.
     */
    public function store(Request $request)
    {
        if (! $request->user()->can('tables.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage tables',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        $validator = Validator::make($request->all(), [
            'name' => [
                'required',
                'string',
                'max:255',
                Rule::unique('restaurant_tables', 'name')
                    ->where(fn ($query) => $query->where('branch_id', $branchId)),
            ],
            'capacity' => 'required|integer|min:1|max:255',
            'status' => [
                'nullable',
                Rule::in(['available', 'occupied', 'reserved']),
            ],
            'section' => 'nullable|string|max:100',
            'shape' => [
                'nullable',
                Rule::in(['square', 'rectangle', 'round']),
            ],
            'color' => 'nullable|string|max:50',
            'is_active' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $table = RestaurantTable::create([
            'branch_id' => $branchId,
            'name' => $request->input('name'),
            'capacity' => $request->input('capacity'),
            'status' => $request->input('status', 'available'),
            'section' => $request->input('section'),
            'shape' => $request->input('shape', 'square'),
            'color' => $request->input('color'),
            'is_active' => $request->input('is_active', true),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Table created successfully',
            'data' => $table->only([
                'id',
                'branch_id',
                'name',
                'capacity',
                'status',
                'section',
                'shape',
                'color',
                'is_active',
            ]),
        ], 201);
    }

    /**
     * PATCH /api/v1/tables/{table}
     *
     * Updates a table belonging to the selected branch.
     */
    public function update(Request $request, RestaurantTable $table)
    {
        if (! $request->user()->can('tables.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage tables',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        if ((int) $table->branch_id !== (int) $branchId) {
            return response()->json([
                'success' => false,
                'message' => 'Table does not belong to the selected branch',
            ], 404);
        }

        $validator = Validator::make($request->all(), [
            'name' => [
                'sometimes',
                'required',
                'string',
                'max:255',
                Rule::unique('restaurant_tables', 'name')
                    ->where(fn ($query) => $query->where('branch_id', $branchId))
                    ->ignore($table->id),
            ],
            'capacity' => 'sometimes|required|integer|min:1|max:255',
            'status' => [
                'sometimes',
                'required',
                Rule::in(['available', 'occupied', 'reserved']),
            ],
            'section' => 'sometimes|nullable|string|max:100',
            'shape' => [
                'sometimes',
                'nullable',
                Rule::in(['square', 'rectangle', 'round']),
            ],
            'color' => 'sometimes|nullable|string|max:50',
            'is_active' => 'sometimes|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $table->update($validator->validated());

        return response()->json([
            'success' => true,
            'message' => 'Table updated successfully',
            'data' => $table->fresh()->only([
                'id',
                'branch_id',
                'name',
                'capacity',
                'status',
                'section',
                'shape',
                'color',
                'is_active',
            ]),
        ]);
    }

    /**
     * DELETE /api/v1/tables/{table}
     *
     * Deletes a table belonging to the selected branch.
     */
    public function destroy(Request $request, RestaurantTable $table)
    {
        if (! $request->user()->can('tables.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage tables',
            ], 403);
        }

        $branchId = $this->resolveBranchId($request);

        if ($branchId instanceof \Illuminate\Http\JsonResponse) {
            return $branchId;
        }

        if ((int) $table->branch_id !== (int) $branchId) {
            return response()->json([
                'success' => false,
                'message' => 'Table does not belong to the selected branch',
            ], 404);
        }

        if ($table->status === 'occupied') {
            return response()->json([
                'success' => false,
                'message' => 'Occupied tables cannot be deleted',
            ], 409);
        }

        $table->delete();

        return response()->json([
            'success' => true,
            'message' => 'Table deleted successfully',
        ]);
    }

    /**
     * Resolve the requested branch while enforcing branch access.
     */
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


