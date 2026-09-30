<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Branch;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class BranchController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('branches.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage branches',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'search' => 'nullable|string|max:255',
            'is_active' => 'nullable|boolean',
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

        $query = Branch::query()
            ->where('business_id', $request->user()->business_id)
            ->withCount('users');

        if ($request->filled('search')) {
            $search = trim($request->input('search'));

            $query->where(function ($query) use ($search) {
                $query->where('name', 'like', "%{$search}%")
                    ->orWhere('code', 'like', "%{$search}%")
                    ->orWhere('address', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        if ($request->has('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        $perPage = (int) $request->input('per_page', 20);

        $branches = $query
            ->orderBy('name')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $branches->map(fn (Branch $branch) => $this->branchData($branch)),
            'meta' => [
                'current_page' => $branches->currentPage(),
                'last_page' => $branches->lastPage(),
                'per_page' => $branches->perPage(),
                'total' => $branches->total(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        if (! $request->user()->can('branches.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage branches',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'code' => 'required|string|max:50|unique:branches,code',
            'address' => 'nullable|string|max:255',
            'phone' => 'nullable|string|max:50',
            'timezone' => 'required|string|max:100',
            'is_active' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $business = $request->user()->business()->with('plan')->first();

        if (! $business || ! $business->plan) {
            return response()->json([
                'success' => false,
                'message' => 'Your business does not have an active plan. Please contact the administrator.',
                'code' => 'PLAN_REQUIRED',
            ], 403);
        }

        $branchCount = $business->branches()->count();

        if ($branchCount >= $business->plan->branch_limit) {
            return response()->json([
                'success' => false,
                'message' => "Your current plan allows up to {$business->plan->branch_limit} branches. Please upgrade your plan to add another branch.",
                'code' => 'BRANCH_LIMIT_REACHED',
                'branch_limit' => $business->plan->branch_limit,
                'branch_count' => $branchCount,
            ], 403);
        }

        $branch = Branch::create(array_merge(
            $validator->validated(),
            ['business_id' => $request->user()->business_id],
        ));

        return response()->json([
            'success' => true,
            'message' => 'Branch created successfully',
            'data' => $this->branchData($branch),
        ], 201);
    }

    public function show(Request $request, Branch $branch)
    {
        if (! $request->user()->can('branches.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage branches',
            ], 403);
        }

        if ($branch->business_id !== $request->user()->business_id) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch',
            ], 403);
        }

        $branch->loadCount('users');

        return response()->json([
            'success' => true,
            'data' => $this->branchData($branch),
        ]);
    }

    public function update(Request $request, Branch $branch)
    {
        if (! $request->user()->can('branches.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage branches',
            ], 403);
        }

        if ($branch->business_id !== $request->user()->business_id) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'code' => 'sometimes|required|string|max:50|unique:branches,code,' . $branch->id,
            'address' => 'nullable|string|max:255',
            'phone' => 'nullable|string|max:50',
            'timezone' => 'sometimes|required|string|max:100',
            'is_active' => 'sometimes|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $branch->update($validator->validated());

        $branch->loadCount('users');

        return response()->json([
            'success' => true,
            'message' => 'Branch updated successfully',
            'data' => $this->branchData($branch),
        ]);
    }

    public function destroy(Request $request, Branch $branch)
    {
        if (! $request->user()->can('branches.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage branches',
            ], 403);
        }

        if ($branch->business_id !== $request->user()->business_id) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch',
            ], 403);
        }

        if ($branch->users()->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot delete a branch that still has assigned users',
            ], 422);
        }

        $branch->delete();

        return response()->json([
            'success' => true,
            'message' => 'Branch deleted successfully',
        ]);
    }

    private function branchData(Branch $branch): array
    {
        return [
            'id' => $branch->id,
            'name' => $branch->name,
            'code' => $branch->code,
            'address' => $branch->address,
            'phone' => $branch->phone,
            'timezone' => $branch->timezone,
            'is_active' => (bool) $branch->is_active,
            'users_count' => (int) ($branch->users_count ?? 0),
            'created_at' => $branch->created_at?->toISOString(),
            'updated_at' => $branch->updated_at?->toISOString(),
        ];
    }
}