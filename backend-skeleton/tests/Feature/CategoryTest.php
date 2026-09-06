<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class CategoryTest extends TestCase
{
    use RefreshDatabase;

    private function makeUserForBranch(Branch $branch, string $role = 'cashier'): User
    {
        Role::firstOrCreate(['name' => $role, 'guard_name' => 'web']);

        $user = User::factory()->create();
        $user->assignRole($role);
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/categories')->assertStatus(401);
    }

    public function test_returns_global_and_own_branch_categories_by_default(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeUserForBranch($branch);

        $global = Category::create(['branch_id' => null, 'name' => 'Coffee', 'sort_order' => 1]);
        $ownBranch = Category::create(['branch_id' => $branch->id, 'name' => 'Seasonal', 'sort_order' => 2]);
        $otherBranchCategory = Category::create(['branch_id' => $otherBranch->id, 'name' => 'Other Branch Only', 'sort_order' => 1]);
        $inactive = Category::create(['branch_id' => null, 'name' => 'Discontinued', 'is_active' => false]);

        $response = $this->actingAs($user)->getJson('/api/v1/categories');

        $response->assertStatus(200)->assertJsonPath('success', true);

        $names = collect($response->json('data'))->pluck('name');
        $this->assertTrue($names->contains('Coffee'));
        $this->assertTrue($names->contains('Seasonal'));
        $this->assertFalse($names->contains('Other Branch Only'));
        $this->assertFalse($names->contains('Discontinued'));
    }

    public function test_explicit_branch_id_for_an_assigned_branch_is_allowed(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        Category::create(['branch_id' => $branch->id, 'name' => 'Seasonal']);

        $response = $this->actingAs($user)->getJson("/api/v1/categories?branch_id={$branch->id}");

        $response->assertStatus(200)->assertJsonPath('success', true);
    }

    public function test_explicit_branch_id_for_an_unassigned_branch_is_rejected(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)->getJson("/api/v1/categories?branch_id={$otherBranch->id}");

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_admin_with_view_all_permission_can_request_any_branch(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);

        Permission::firstOrCreate(['name' => 'branches.view-all', 'guard_name' => 'web']);
        $adminRole = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $adminRole->syncPermissions(['branches.view-all']);

        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        Category::create(['branch_id' => $otherBranch->id, 'name' => 'Other Branch Category']);

        $response = $this->actingAs($admin)->getJson("/api/v1/categories?branch_id={$otherBranch->id}");

        $response->assertStatus(200)->assertJsonPath('success', true);
        $this->assertTrue(collect($response->json('data'))->pluck('name')->contains('Other Branch Category'));
    }

    public function test_user_with_no_assigned_branch_gets_a_clear_error(): void
    {
        Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
        $user = User::factory()->create();
        $user->assignRole('cashier');
        // Deliberately no branch attached.

        $response = $this->actingAs($user)->getJson('/api/v1/categories');

        $response->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_invalid_branch_id_fails_validation(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)->getJson('/api/v1/categories?branch_id=999999');

        $response->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_categories_are_ordered_by_sort_order(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);

        Category::create(['branch_id' => null, 'name' => 'Second', 'sort_order' => 2]);
        Category::create(['branch_id' => null, 'name' => 'First', 'sort_order' => 1]);

        $response = $this->actingAs($user)->getJson('/api/v1/categories');

        $names = collect($response->json('data'))->pluck('name')->values()->all();
        $this->assertSame(['First', 'Second'], $names);
    }
}
