<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class SupplierTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach ([
            'inventory.view',
            'inventory.manage',
            'branches.view-all',
        ] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        $cashier = Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ]);

        $cashier->syncPermissions([
            'inventory.view',
        ]);

        $manager = Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);

        $manager->syncPermissions([
            'inventory.view',
            'inventory.manage',
        ]);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);

        $admin->syncPermissions([
            'inventory.view',
            'inventory.manage',
            'branches.view-all',
        ]);
    }

    private function makeUser(Branch $branch, string $role = 'manager'): User
    {
        $this->seedPermissions();

        $user = User::factory()->create();
        $user->assignRole($role);

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $response = $this->getJson('/api/v1/suppliers');

        $response->assertStatus(401);
    }

    public function test_user_without_inventory_view_permission_is_rejected(): void
    {
        $branch = Branch::factory()->create();

        $this->seedPermissions();

        $user = User::factory()->create();

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/suppliers');

        $response->assertStatus(403);
    }

    public function test_user_can_list_suppliers_for_their_branch_and_global_suppliers(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);

        $globalSupplier = Supplier::create([
            'branch_id' => null,
            'name' => 'Global Coffee Supplier',
        ]);

        $branchSupplier = Supplier::create([
            'branch_id' => $branch->id,
            'name' => 'Branch Coffee Supplier',
        ]);

        Supplier::create([
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Supplier',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/suppliers');

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonCount(2, 'data');

        $response->assertJsonFragment([
            'id' => $globalSupplier->id,
            'name' => 'Global Coffee Supplier',
        ]);

        $response->assertJsonFragment([
            'id' => $branchSupplier->id,
            'name' => 'Branch Coffee Supplier',
        ]);

        $response->assertJsonMissing([
            'id' => $otherBranch->id,
            'name' => 'Other Branch Supplier',
        ]);
    }

    public function test_user_cannot_list_another_branch_without_access(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/suppliers?branch_id=' . $otherBranch->id);

        $response->assertStatus(403);
    }

    public function test_manager_can_create_branch_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/suppliers', [
                'branch_id' => $branch->id,
                'name' => 'Fresh Beans Supplier',
                'contact_name' => 'John',
                'phone' => '012345678',
                'email' => 'supplier@example.com',
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Fresh Beans Supplier')
            ->assertJsonPath('data.branch_id', $branch->id);

        $this->assertDatabaseHas('suppliers', [
            'branch_id' => $branch->id,
            'name' => 'Fresh Beans Supplier',
            'contact_name' => 'John',
            'phone' => '012345678',
            'email' => 'supplier@example.com',
        ]);
    }

    public function test_regular_branch_user_cannot_create_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/suppliers', [
                'branch_id' => null,
                'name' => 'Global Supplier',
            ]);

        $response->assertStatus(403);

        $this->assertDatabaseMissing('suppliers', [
            'name' => 'Global Supplier',
        ]);
    }

    public function test_manager_cannot_create_supplier_for_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/suppliers', [
                'branch_id' => $otherBranch->id,
                'name' => 'Other Branch Supplier',
            ]);

        $response->assertStatus(403);
    }

    public function test_admin_can_create_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch, 'admin');

        $response = $this->actingAs($user)
            ->postJson('/api/v1/suppliers', [
                'branch_id' => null,
                'name' => 'Global Supplier',
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.branch_id', null)
            ->assertJsonPath('data.name', 'Global Supplier');

        $this->assertDatabaseHas('suppliers', [
            'branch_id' => null,
            'name' => 'Global Supplier',
        ]);
    }

    public function test_manager_can_update_supplier_in_their_branch(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $supplier = Supplier::create([
            'branch_id' => $branch->id,
            'name' => 'Old Supplier Name',
        ]);

        $response = $this->actingAs($user)
            ->patchJson('/api/v1/suppliers/' . $supplier->id, [
                'branch_id' => $branch->id,
                'name' => 'Updated Supplier Name',
                'contact_name' => 'Jane',
            ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Updated Supplier Name')
            ->assertJsonPath('data.contact_name', 'Jane');

        $this->assertDatabaseHas('suppliers', [
            'id' => $supplier->id,
            'name' => 'Updated Supplier Name',
            'contact_name' => 'Jane',
        ]);
    }

    public function test_manager_cannot_update_supplier_from_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);

        $supplier = Supplier::create([
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Supplier',
        ]);

        $response = $this->actingAs($user)
            ->patchJson('/api/v1/suppliers/' . $supplier->id, [
                'branch_id' => $otherBranch->id,
                'name' => 'Hacked Supplier',
            ]);

        $response->assertStatus(403);

        $this->assertDatabaseHas('suppliers', [
            'id' => $supplier->id,
            'name' => 'Other Branch Supplier',
        ]);
    }

    public function test_manager_cannot_update_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $supplier = Supplier::create([
            'branch_id' => null,
            'name' => 'Global Supplier',
        ]);

        $response = $this->actingAs($user)
            ->patchJson('/api/v1/suppliers/' . $supplier->id, [
                'branch_id' => null,
                'name' => 'Changed Global Supplier',
            ]);

        $response->assertStatus(403);

        $this->assertDatabaseHas('suppliers', [
            'id' => $supplier->id,
            'name' => 'Global Supplier',
        ]);
    }

    public function test_admin_can_update_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch, 'admin');

        $supplier = Supplier::create([
            'branch_id' => null,
            'name' => 'Global Supplier',
        ]);

        $response = $this->actingAs($user)
            ->patchJson('/api/v1/suppliers/' . $supplier->id, [
                'branch_id' => null,
                'name' => 'Updated Global Supplier',
            ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Updated Global Supplier');
    }

    public function test_manager_can_soft_delete_supplier_in_their_branch(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $supplier = Supplier::create([
            'branch_id' => $branch->id,
            'name' => 'Supplier To Delete',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson('/api/v1/suppliers/' . $supplier->id);

        $response->assertOk()
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('suppliers', [
            'id' => $supplier->id,
        ]);
    }

    public function test_manager_cannot_delete_supplier_from_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);

        $supplier = Supplier::create([
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Supplier',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson('/api/v1/suppliers/' . $supplier->id);

        $response->assertStatus(403);

        $this->assertDatabaseHas('suppliers', [
            'id' => $supplier->id,
            'deleted_at' => null,
        ]);
    }

    public function test_admin_can_delete_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch, 'admin');

        $supplier = Supplier::create([
            'branch_id' => null,
            'name' => 'Global Supplier',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson('/api/v1/suppliers/' . $supplier->id);

        $response->assertOk();

        $this->assertSoftDeleted('suppliers', [
            'id' => $supplier->id,
        ]);
    }

    public function test_validation_rejects_missing_supplier_name(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/suppliers', [
                'branch_id' => $branch->id,
            ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }
}