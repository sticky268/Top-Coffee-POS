<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;

use App\Models\Branch;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Spatie\Permission\Models\Role;

class UserController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->user()->can('users.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage users',
            ], 403);
        }

        $validator = Validator::make($request->query(), [
            'branch_id' => 'nullable|integer|exists:branches,id',
            'role' => 'nullable|string|max:100',
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

        $user = $request->user();
        $branchId = $request->query('branch_id');

        if ($branchId !== null) {
            $branchId = (int) $branchId;

            if (! $this->canAccessBranch($user, $branchId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }
        }

        $query = User::query()
            ->with([
                'roles:id,name',
                'branches:id,name,code',
            ]);

        if ($branchId !== null) {
            $query->whereHas('branches', function ($query) use ($branchId) {
                $query->where('branches.id', $branchId);
            });
        } else if (! $user->can('branches.view-all')) {
            $branchIds = $user->branches()->pluck('branches.id');

            $query->whereHas('branches', function ($query) use ($branchIds) {
                $query->whereIn('branches.id', $branchIds);
            });
        }

        if (! $user->hasRole('admin')) {
            $query->whereDoesntHave('roles', function ($query) {
                $query->whereIn('name', ['admin', 'manager']);
            });
        }

        if ($request->filled('role')) {
            $query->role($request->input('role'));
        }

        if ($request->filled('search')) {
            $search = trim($request->input('search'));

            $query->where(function ($query) use ($search) {
                $query->where('name', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        if ($request->has('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        $perPage = (int) $request->input('per_page', 20);

        $users = $query
            ->orderBy('name')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $users->map(fn (User $user) => $this->userData($user)),
            'meta' => [
                'current_page' => $users->currentPage(),
                'last_page' => $users->lastPage(),
                'per_page' => $users->perPage(),
                'total' => $users->total(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        if (! $request->user()->can('users.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage users',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255|unique:users,email',
            'phone' => 'nullable|string|max:50',
            'password' => 'required|string|min:8',
            'role' => 'required|string|exists:roles,name',
            'branch_ids' => 'required|array|min:1',
            'branch_ids.*' => 'integer|distinct|exists:branches,id',
            'primary_branch_id' => 'required|integer',
            'is_active' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();
        $actor = $request->user();

        if (! $this->canManageRole($actor, $data['role'])) {
            return response()->json([
                'success' => false,
                'message' => 'You cannot assign that role',
            ], 403);
        }

        $branchIds = array_map('intval', $data['branch_ids']);
        $primaryBranchId = (int) $data['primary_branch_id'];

        if (! in_array($primaryBranchId, $branchIds, true)) {
            return response()->json([
                'success' => false,
                'message' => 'The primary branch must be one of the assigned branches',
            ], 422);
        }

        if (! $this->canAccessBranches($actor, $branchIds)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to one or more selected branches',
            ], 403);
        }

        $user = DB::transaction(function () use ($data, $branchIds, $primaryBranchId) {
            $user = User::create([
                'name' => $data['name'],
                'email' => $data['email'],
                'phone' => $data['phone'] ?? null,
                'password' => Hash::make($data['password']),
                'is_active' => $data['is_active'] ?? true,
            ]);

            $user->assignRole($data['role']);

            $this->syncBranches($user, $branchIds, $primaryBranchId);

            return $user->load([
                'roles:id,name',
                'branches:id,name,code',
            ]);
        });

        return response()->json([
            'success' => true,
            'message' => 'User created successfully',
            'data' => $this->userData($user),
        ], 201);
    }

    public function show(Request $request, User $user)
    {
        if (! $request->user()->can('users.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage users',
            ], 403);
        }

        if (! $this->canManageUser($request->user(), $user)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to that user',
            ], 403);
        }

        $user->load([
            'roles:id,name',
            'branches:id,name,code',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->userData($user),
        ]);
    }

    public function update(Request $request, User $user)
    {
        if (! $request->user()->can('users.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage users',
            ], 403);
        }

        $actor = $request->user();

        if (! $this->canManageUser($actor, $user)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to that user',
            ], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'email' => 'sometimes|required|email|max:255|unique:users,email,' . $user->id,
            'phone' => 'nullable|string|max:50',
            'password' => 'nullable|string|min:8',
            'role' => 'sometimes|required|string|exists:roles,name',
            'branch_ids' => 'sometimes|required|array|min:1',
            'branch_ids.*' => 'integer|distinct|exists:branches,id',
            'primary_branch_id' => 'sometimes|required|integer',
            'is_active' => 'sometimes|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        if (isset($data['role']) && ! $this->canManageRole($actor, $data['role'])) {
            return response()->json([
                'success' => false,
                'message' => 'You cannot assign that role',
            ], 403);
        }

        if (
            $user->id === $actor->id
            && array_key_exists('is_active', $data)
            && $data['is_active'] === false
        ) {
            return response()->json([
                'success' => false,
                'message' => 'You cannot deactivate your own account',
            ], 422);
        }

        $branchIds = null;
        $primaryBranchId = null;

        if (array_key_exists('branch_ids', $data)) {
            $branchIds = array_map('intval', $data['branch_ids']);
            $primaryBranchId = (int) ($data['primary_branch_id'] ?? $user->branches()
                ->wherePivot('is_primary', true)
                ->value('branches.id'));

            if (! in_array($primaryBranchId, $branchIds, true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'The primary branch must be one of the assigned branches',
                ], 422);
            }

            if (! $this->canAccessBranches($actor, $branchIds)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to one or more selected branches',
                ], 403);
            }
        } elseif (array_key_exists('primary_branch_id', $data)) {
            $primaryBranchId = (int) $data['primary_branch_id'];

            if (! $this->canAccessBranch($actor, $primaryBranchId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You do not have access to that branch',
                ], 403);
            }

            if (! $user->branches()->where('branches.id', $primaryBranchId)->exists()) {
                return response()->json([
                    'success' => false,
                    'message' => 'The primary branch must be assigned to the user',
                ], 422);
            }
        }

        DB::transaction(function () use ($user, $data, $branchIds, $primaryBranchId) {
            $update = [];

            foreach (['name', 'email', 'phone', 'is_active'] as $field) {
                if (array_key_exists($field, $data)) {
                    $update[$field] = $data[$field];
                }
            }

            if (array_key_exists('password', $data) && $data['password'] !== null) {
                $update['password'] = Hash::make($data['password']);
            }

            if ($update !== []) {
                $user->update($update);
            }

            if (isset($data['role'])) {
                $user->syncRoles([$data['role']]);
            }

            if ($branchIds !== null) {
                $this->syncBranches($user, $branchIds, $primaryBranchId);
            } elseif ($primaryBranchId !== null) {
                $user->branches()->updateExistingPivot($primaryBranchId, [
                    'is_primary' => true,
                ]);

                $user->branches()
                    ->where('branches.id', '!=', $primaryBranchId)
                    ->get()
                    ->each(function (Branch $branch) use ($user) {
                        $user->branches()->updateExistingPivot($branch->id, [
                            'is_primary' => false,
                        ]);
                    });
            }
        });

        $user->load([
            'roles:id,name',
            'branches:id,name,code',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'User updated successfully',
            'data' => $this->userData($user),
        ]);
    }

    public function destroy(Request $request, User $user)
    {
        if (! $request->user()->can('users.manage')) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have permission to manage users',
            ], 403);
        }

        $actor = $request->user();

        if (! $this->canManageUser($actor, $user)) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to that user',
            ], 403);
        }

        if ($user->id === $actor->id) {
            return response()->json([
                'success' => false,
                'message' => 'You cannot delete your own account',
            ], 422);
        }

        $user->delete();

        return response()->json([
            'success' => true,
            'message' => 'User deleted successfully',
        ]);
    }

    private function userData(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
            'is_active' => (bool) $user->is_active,
            'roles' => $user->getRoleNames()->values(),
            'branches' => $user->branches->map(fn (Branch $branch) => [
                'id' => $branch->id,
                'name' => $branch->name,
                'code' => $branch->code,
                'is_primary' => (bool) $branch->pivot->is_primary,
            ])->values(),
        ];
    }

    private function canManageRole(User $actor, string $role): bool
    {
        if ($actor->hasRole('admin')) {
            return Role::where('name', $role)->exists();
        }

        return in_array($role, ['cashier', 'kitchen_staff'], true);
    }

    private function canManageUser(User $actor, User $target): bool
    {
        if ($actor->hasRole('admin')) {
            return true;
        }

        if ($target->hasRole('admin') || $target->hasRole('manager')) {
            return false;
        }

        $actorBranchIds = $actor->branches()->pluck('branches.id');

        return $target->branches()
            ->whereIn('branches.id', $actorBranchIds)
            ->exists();
    }

    private function canAccessBranch(User $user, int $branchId): bool
    {
        return $user->can('branches.view-all')
            || $user->branches()->where('branches.id', $branchId)->exists();
    }

    private function canAccessBranches(User $user, array $branchIds): bool
    {
        if ($user->can('branches.view-all')) {
            return true;
        }

        $accessibleCount = $user->branches()
            ->whereIn('branches.id', $branchIds)
            ->count();

        return $accessibleCount === count(array_unique($branchIds));
    }

    private function syncBranches(User $user, array $branchIds, int $primaryBranchId): void
    {
        $syncData = [];

        foreach ($branchIds as $branchId) {
            $syncData[$branchId] = [
                'is_primary' => $branchId === $primaryBranchId,
            ];
        }

        $user->branches()->sync($syncData);
    }
}
