<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Supplier;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class SupplierController extends Controller
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
            $branchId = $user->branches()
                ->orderBy('branches.id')
                ->value('branches.id');
        }

        if ($branchId === null) {
            return response()->json([
                'success' => false,
                'message' => 'No branch is available for this user.',
            ], 422);
        }

        $suppliers = Supplier::query()
            ->where(function ($query) use ($branchId) {
                $query->whereNull('branch_id')
                    ->orWhere('branch_id', $branchId);
            })
            ->orderBy('name')
            ->get([
                'id',
                'branch_id',
                'name',
                'contact_name',
                'phone',
                'email',
            ]);

        return response()->json([
            'success' => true,
            'data' => $suppliers,
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
                'name' => ['required', 'string', 'max:255'],
                'contact_name' => ['nullable', 'string', 'max:255'],
                'phone' => ['nullable', 'string', 'max:50'],
                'email' => ['nullable', 'email', 'max:255'],
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
            if (! $user->can('branches.view-all')) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only users with access to all branches can create a global supplier.',
                ], 403);
            }
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

        $supplier = Supplier::create([
            'branch_id' => $branchId,
            'name' => $request->input('name'),
            'contact_name' => $request->input('contact_name'),
            'phone' => $request->input('phone'),
            'email' => $request->input('email'),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Supplier created successfully.',
            'data' => $supplier,
        ], 201);
    }

    public function update(Request $request, $id)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $supplier = Supplier::query()
            ->whereKey($id)
            ->first();

        if (! $supplier) {
            return response()->json([
                'success' => false,
                'message' => 'Supplier not found.',
            ], 404);
        }

        $user = $request->user();

        if (
            $supplier->branch_id === null
            && ! $user->can('branches.view-all')
        ) {
            return response()->json([
                'success' => false,
                'message' => 'Only users with access to all branches can modify a global supplier.',
            ], 403);
        }

        if (
            $supplier->branch_id !== null
            && ! $user->can('branches.view-all')
            && ! $user->branches()
                ->where('branches.id', $supplier->branch_id)
                ->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this supplier.',
            ], 403);
        }

        $validator = Validator::make(
            $request->all(),
            [
                'branch_id' => ['nullable', 'integer', 'exists:branches,id'],
                'name' => ['required', 'string', 'max:255'],
                'contact_name' => ['nullable', 'string', 'max:255'],
                'phone' => ['nullable', 'string', 'max:50'],
                'email' => ['nullable', 'email', 'max:255'],
            ]
        );

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $newBranchId = $request->input('branch_id');

        if ($newBranchId === null) {
            if (! $user->can('branches.view-all')) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only users with access to all branches can assign a supplier globally.',
                ], 403);
            }
        } elseif (
            ! $user->can('branches.view-all')
            && ! $user->branches()
                ->where('branches.id', $newBranchId)
                ->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this branch.',
            ], 403);
        }

        $supplier->update([
            'branch_id' => $newBranchId,
            'name' => $request->input('name'),
            'contact_name' => $request->input('contact_name'),
            'phone' => $request->input('phone'),
            'email' => $request->input('email'),
        ]);

        $supplier->refresh();

        return response()->json([
            'success' => true,
            'message' => 'Supplier updated successfully.',
            'data' => $supplier,
        ]);
    }

    public function destroy(Request $request, $id)
    {
        if (! $request->user()->can('inventory.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $supplier = Supplier::query()
            ->whereKey($id)
            ->first();

        if (! $supplier) {
            return response()->json([
                'success' => false,
                'message' => 'Supplier not found.',
            ], 404);
        }

        $user = $request->user();

        if (
            $supplier->branch_id === null
            && ! $user->can('branches.view-all')
        ) {
            return response()->json([
                'success' => false,
                'message' => 'Only users with access to all branches can delete a global supplier.',
            ], 403);
        }

        if (
            $supplier->branch_id !== null
            && ! $user->can('branches.view-all')
            && ! $user->branches()
                ->where('branches.id', $supplier->branch_id)
                ->exists()
        ) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this supplier.',
            ], 403);
        }

        $supplier->delete();

        return response()->json([
            'success' => true,
            'message' => 'Supplier deleted successfully.',
        ]);
    }
}