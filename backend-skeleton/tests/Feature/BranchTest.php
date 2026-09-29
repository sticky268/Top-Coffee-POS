<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class BranchTest extends TestCase
{
    use RefreshDatabase;

    private function setupPermissions(): void
    {
        foreach (['branches.manage'] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        foreach (['admin', 'manager', 'cashier'] as $role) {
            Role::firstOrCreate([
                'name' => $role,
                'guard_name' => 'web',
            ]);
        }
    }

    private function makeUser(bool $canManageBranches = true): User
    {
        $this->setupPermissions();

        $role = Role::where('name', 'admin')->firstOrFail();

        $role->syncPermissions(
            $canManageBranches ? ['branches.manage'] : []
        );

        $user = User::factory()->create([
            'is_active' => true,
        ]);

        $user->assignRole($role);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/branches')
            ->assertStatus(401);
    }

    public function test_user_without_branches_manage_permission_is_rejected(): void
    {
        $user = $this->makeUser(false);

        $this->actingAs($user)
            ->getJson('/api/v1/branches')
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_authorized_user_can_list_branches(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/branches');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('meta.total', 2);
    }

    public function test_branch_list_supports_search_and_active_filter(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
            'is_active' => true,
        ]);

        Branch::create([
            'name' => 'BKK1',
            'code' => 'PP-02',
            'is_active' => false,
        ]);

        $searchResponse = $this->actingAs($user)
            ->getJson('/api/v1/branches?search=Riverside');

        $searchResponse
            ->assertStatus(200)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'PP-01');

        $activeResponse = $this->actingAs($user)
            ->getJson('/api/v1/branches?is_active=1');

        $activeResponse
            ->assertStatus(200)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'PP-01');
    }

    public function test_authorized_user_can_create_branch(): void
    {
        $user = $this->makeUser();

        $response = $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Riverside',
                'code' => 'PP-01',
                'address' => 'Phnom Penh',
                'phone' => '012345678',
                'timezone' => 'Asia/Phnom_Penh',
                'is_active' => true,
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Riverside')
            ->assertJsonPath('data.code', 'PP-01')
            ->assertJsonPath('data.is_active', true)
            ->assertJsonPath('data.users_count', 0);

        $this->assertDatabaseHas('branches', [
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);
    }

    public function test_duplicate_branch_code_is_rejected(): void
    {
        $user = $this->makeUser();

        Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->postJson('/api/v1/branches', [
                'name' => 'Another Branch',
                'code' => 'PP-01',
                'timezone' => 'Asia/Phnom_Penh',
            ])
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_authorized_user_can_show_branch(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->getJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $branch->id)
            ->assertJsonPath('data.name', 'Riverside')
            ->assertJsonPath('data.users_count', 0);
    }

    public function test_authorized_user_can_update_branch(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->patchJson("/api/v1/branches/{$branch->id}", [
                'name' => 'Riverside Updated',
                'phone' => '099999999',
                'is_active' => false,
            ])
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Riverside Updated')
            ->assertJsonPath('data.phone', '099999999')
            ->assertJsonPath('data.is_active', false);

        $this->assertDatabaseHas('branches', [
            'id' => $branch->id,
            'name' => 'Riverside Updated',
            'phone' => '099999999',
            'is_active' => false,
        ]);
    }

    public function test_authorized_user_can_delete_branch_without_users(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $this->actingAs($user)
            ->deleteJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('branches', [
            'id' => $branch->id,
        ]);
    }

    public function test_branch_with_assigned_users_cannot_be_deleted(): void
    {
        $user = $this->makeUser();

        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $staff = User::factory()->create([
            'is_active' => true,
        ]);

        $branch->users()->attach($staff->id, [
            'is_primary' => true,
        ]);

        $this->actingAs($user)
            ->deleteJson("/api/v1/branches/{$branch->id}")
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('branches', [
            'id' => $branch->id,
            'deleted_at' => null,
        ]);
    }
}