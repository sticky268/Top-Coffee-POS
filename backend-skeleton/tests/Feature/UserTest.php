<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class UserTest extends TestCase
{
    use RefreshDatabase;

    private function setupPermissions(): void
    {
        foreach (['users.manage', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        foreach (['admin', 'manager', 'cashier', 'kitchen_staff'] as $role) {
            Role::firstOrCreate([
                'name' => $role,
                'guard_name' => 'web',
            ]);
        }
    }

    private function makeUser(
        Branch $branch,
        string $role = 'cashier',
        bool $usersManage = true
    ): User {
        $this->setupPermissions();

        $roleModel = Role::where('name', $role)->firstOrFail();

        if ($role === 'admin') {
            $roleModel->syncPermissions(['users.manage', 'branches.view-all']);
        } elseif ($role === 'manager') {
            $roleModel->syncPermissions($usersManage ? ['users.manage'] : []);
        } elseif ($usersManage) {
            $roleModel->syncPermissions(['users.manage']);
        } else {
            $roleModel->syncPermissions([]);
        }

        $user = User::factory()->create([
            'is_active' => true,
        ]);

        $user->assignRole($role);
        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/users')
            ->assertStatus(401);
    }

    public function test_user_without_users_manage_permission_is_rejected(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeUser($branch, 'cashier', false);

        $this->actingAs($user)
            ->getJson('/api/v1/users')
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_admin_can_list_staff_from_all_branches(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeUser($branch1, 'admin');

        $cashier = $this->makeUser($branch1, 'cashier');

        $otherBranchCashier = User::factory()->create([
            'name' => 'Other Branch Cashier',
        ]);
        $otherBranchCashier->assignRole('cashier');
        $otherBranchCashier->branches()->attach($branch2->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($admin)
            ->getJson('/api/v1/users');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $ids = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($admin->id));
        $this->assertTrue($ids->contains($cashier->id));
        $this->assertTrue($ids->contains($otherBranchCashier->id));
    }

    public function test_manager_only_sees_manageable_staff_in_own_branches(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $manager = $this->makeUser($branch1, 'manager');

        $cashier = $this->makeUser($branch1, 'cashier');
        $kitchen = User::factory()->create([
            'name' => 'Kitchen Staff',
        ]);
        $kitchen->assignRole('kitchen_staff');
        $kitchen->branches()->attach($branch1->id, [
            'is_primary' => true,
        ]);

        $otherBranchCashier = User::factory()->create([
            'name' => 'Other Branch Cashier',
        ]);
        $otherBranchCashier->assignRole('cashier');
        $otherBranchCashier->branches()->attach($branch2->id, [
            'is_primary' => true,
        ]);

        $admin = User::factory()->create([
            'name' => 'Admin User',
        ]);
        $admin->assignRole('admin');
        $admin->branches()->attach($branch1->id, [
            'is_primary' => true,
        ]);

        $otherManager = User::factory()->create([
            'name' => 'Other Manager',
        ]);
        $otherManager->assignRole('manager');
        $otherManager->branches()->attach($branch1->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($manager)
            ->getJson('/api/v1/users');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $ids = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($cashier->id));
        $this->assertTrue($ids->contains($kitchen->id));
        $this->assertFalse($ids->contains($otherBranchCashier->id));
        $this->assertFalse($ids->contains($admin->id));
        $this->assertFalse($ids->contains($otherManager->id));
    }

    public function test_admin_can_create_manager_with_multiple_branches(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeUser($branch1, 'admin');

        $response = $this->actingAs($admin)
            ->postJson('/api/v1/users', [
                'name' => 'New Manager',
                'email' => 'new.manager@example.com',
                'phone' => '012345678',
                'password' => 'password123',
                'role' => 'manager',
                'branch_ids' => [$branch1->id, $branch2->id],
                'primary_branch_id' => $branch2->id,
                'is_active' => true,
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'New Manager')
            ->assertJsonPath('data.roles.0', 'manager');

        $user = User::where('email', 'new.manager@example.com')->firstOrFail();

        $this->assertDatabaseHas('user_branch', [
            'user_id' => $user->id,
            'branch_id' => $branch1->id,
            'is_primary' => false,
        ]);

        $this->assertDatabaseHas('user_branch', [
            'user_id' => $user->id,
            'branch_id' => $branch2->id,
            'is_primary' => true,
        ]);
    }

    public function test_manager_can_create_cashier_but_cannot_create_manager(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $manager = $this->makeUser($branch, 'manager');

        $cashierResponse = $this->actingAs($manager)
            ->postJson('/api/v1/users', [
                'name' => 'New Cashier',
                'email' => 'new.cashier@example.com',
                'password' => 'password123',
                'role' => 'cashier',
                'branch_ids' => [$branch->id],
                'primary_branch_id' => $branch->id,
            ]);

        $cashierResponse
            ->assertStatus(201)
            ->assertJsonPath('data.roles.0', 'cashier');

        $managerResponse = $this->actingAs($manager)
            ->postJson('/api/v1/users', [
                'name' => 'Blocked Manager',
                'email' => 'blocked.manager@example.com',
                'password' => 'password123',
                'role' => 'manager',
                'branch_ids' => [$branch->id],
                'primary_branch_id' => $branch->id,
            ]);

        $managerResponse
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_create_rejects_primary_branch_not_in_assignments(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeUser($branch1, 'admin');

        $response = $this->actingAs($admin)
            ->postJson('/api/v1/users', [
                'name' => 'Invalid Branch User',
                'email' => 'invalid.branch@example.com',
                'password' => 'password123',
                'role' => 'cashier',
                'branch_ids' => [$branch1->id],
                'primary_branch_id' => $branch2->id,
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseMissing('users', [
            'email' => 'invalid.branch@example.com',
        ]);
    }

    public function test_manager_cannot_assign_staff_to_unassigned_branch(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $manager = $this->makeUser($branch1, 'manager');

        $response = $this->actingAs($manager)
            ->postJson('/api/v1/users', [
                'name' => 'Blocked Branch User',
                'email' => 'blocked.branch@example.com',
                'password' => 'password123',
                'role' => 'cashier',
                'branch_ids' => [$branch2->id],
                'primary_branch_id' => $branch2->id,
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseMissing('users', [
            'email' => 'blocked.branch@example.com',
        ]);
    }

    public function test_manager_cannot_show_or_update_admin_or_manager(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $manager = $this->makeUser($branch, 'manager');

        $admin = User::factory()->create([
            'name' => 'Admin User',
        ]);
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $otherManager = User::factory()->create([
            'name' => 'Other Manager',
        ]);
        $otherManager->assignRole('manager');
        $otherManager->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $this->actingAs($manager)
            ->getJson("/api/v1/users/{$admin->id}")
            ->assertStatus(403);

        $this->actingAs($manager)
            ->getJson("/api/v1/users/{$otherManager->id}")
            ->assertStatus(403);

        $this->actingAs($manager)
            ->patchJson("/api/v1/users/{$admin->id}", [
                'name' => 'Changed Admin',
            ])
            ->assertStatus(403);

        $this->actingAs($manager)
            ->patchJson("/api/v1/users/{$otherManager->id}", [
                'name' => 'Changed Manager',
            ])
            ->assertStatus(403);
    }

    public function test_update_can_change_profile_role_branches_and_status(): void
    {
        $branch1 = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branch2 = Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeUser($branch1, 'admin');

        $cashier = User::factory()->create([
            'name' => 'Old Cashier',
            'email' => 'old.cashier@example.com',
            'is_active' => true,
        ]);
        $cashier->assignRole('cashier');
        $cashier->branches()->attach($branch1->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($admin)
            ->patchJson("/api/v1/users/{$cashier->id}", [
                'name' => 'Updated Cashier',
                'phone' => '098765432',
                'role' => 'kitchen_staff',
                'branch_ids' => [$branch1->id, $branch2->id],
                'primary_branch_id' => $branch2->id,
                'is_active' => false,
                'password' => 'newpassword123',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('data.name', 'Updated Cashier')
            ->assertJsonPath('data.phone', '098765432')
            ->assertJsonPath('data.roles.0', 'kitchen_staff')
            ->assertJsonPath('data.is_active', false);

        $this->assertDatabaseHas('users', [
            'id' => $cashier->id,
            'name' => 'Updated Cashier',
            'phone' => '098765432',
            'is_active' => false,
        ]);

        $this->assertDatabaseHas('user_branch', [
            'user_id' => $cashier->id,
            'branch_id' => $branch1->id,
            'is_primary' => false,
        ]);

        $this->assertDatabaseHas('user_branch', [
            'user_id' => $cashier->id,
            'branch_id' => $branch2->id,
            'is_primary' => true,
        ]);

        $this->assertTrue(
            \Illuminate\Support\Facades\Hash::check(
                'newpassword123',
                $cashier->fresh()->password
            )
        );
    }

    public function test_admin_cannot_deactivate_own_account(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $admin = $this->makeUser($branch, 'admin');

        $response = $this->actingAs($admin)
            ->patchJson("/api/v1/users/{$admin->id}", [
                'is_active' => false,
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('users', [
            'id' => $admin->id,
            'is_active' => true,
        ]);
    }

    public function test_admin_cannot_delete_own_account(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $admin = $this->makeUser($branch, 'admin');

        $response = $this->actingAs($admin)
            ->deleteJson("/api/v1/users/{$admin->id}");

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('users', [
            'id' => $admin->id,
            'deleted_at' => null,
        ]);
    }

    public function test_delete_soft_deletes_staff(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $admin = $this->makeUser($branch, 'admin');

        $cashier = User::factory()->create();
        $cashier->assignRole('cashier');
        $cashier->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($admin)
            ->deleteJson("/api/v1/users/{$cashier->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('users', [
            'id' => $cashier->id,
        ]);
    }

    public function test_list_supports_search_role_and_active_filters(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $admin = $this->makeUser($branch, 'admin');

        $cashier = User::factory()->create([
            'name' => 'Dara Cashier',
            'email' => 'dara@example.com',
            'phone' => '012345678',
            'is_active' => true,
        ]);
        $cashier->assignRole('cashier');
        $cashier->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $kitchen = User::factory()->create([
            'name' => 'Sokha Kitchen',
            'is_active' => false,
        ]);
        $kitchen->assignRole('kitchen_staff');
        $kitchen->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($admin)
            ->getJson('/api/v1/users?search=012345678&role=cashier&is_active=1');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Dara Cashier');
    }
}