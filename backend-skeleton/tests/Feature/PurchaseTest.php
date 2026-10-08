<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Ingredient;
use App\Models\Purchase;
use App\Models\Supplier;
use App\Models\User;
use App\Services\StockMovementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class PurchaseTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach ([
            'inventory.manage',
            'inventory.view',
            'branches.view-all',
        ] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        $manager = Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);

        $manager->syncPermissions([
            'inventory.manage',
            'inventory.view',
        ]);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);

        $admin->syncPermissions([
            'inventory.manage',
            'branches.view-all',
        ]);
    }

    private function createUnit(): int
    {
        return DB::table('units')->insertGetId([
            'name' => 'Gram',
            'abbreviation' => 'g',
            'base_unit_id' => null,
            'conversion_factor' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function makeUser(Branch $branch, string $role = 'manager'): User
    {
        $this->seedPermissions();

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole($role);

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    private function createIngredient(
        Branch $branch,
        string $name = 'Coffee Beans',
        float $stock = 0,
    ): Ingredient {
        $unitId = $this->createUnit();

        $ingredient = Ingredient::create([
            'branch_id' => $branch->id,
            'unit_id' => $unitId,
            'name' => $name,
            'reorder_threshold' => 0,
            'is_active' => true,
        ]);

        if ($stock > 0) {
            $createdBy = User::query()
                ->whereHas('branches', fn ($query) => $query->where('branches.id', $branch->id))
                ->value('id');

            if ($createdBy === null) {
                throw new \RuntimeException(
                    'No test user is assigned to the ingredient branch.'
                );
            }

            app(StockMovementService::class)->record(
                $ingredient,
                'purchase',
                $stock,
                $createdBy,
                'Initial test stock',
            );

            $ingredient->refresh();
        }

        return $ingredient;
    }

    private function createSupplier(
        ?int $branchId,
        string $name = 'Coffee Supplier',
    ): Supplier {
        return Supplier::create([
            'branch_id' => $branchId,
            'name' => $name,
        ]);
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $response = $this->postJson('/api/v1/purchases', []);

        $response->assertStatus(401);
    }

    public function test_user_without_inventory_manage_permission_is_rejected(): void
    {
        $branch = Branch::factory()->create();

        $this->seedPermissions();

        $user = User::factory()->create();

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', []);

        $response->assertStatus(403);
    }

    public function test_manager_can_create_purchase_and_increase_stock(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredient = $this->createIngredient($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 10,
                        'unit_cost' => 2.50,
                    ],
                ],
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.total_cost', '25.00');

        $purchaseId = $response->json('data.id');

        $this->assertDatabaseHas('purchases', [
            'id' => $purchaseId,
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'created_by' => $user->id,
            'total_cost' => 25.00,
            'purchased_at' => '2026-09-17 00:00:00',
        ]);

        $this->assertDatabaseHas('purchase_items', [
            'purchase_id' => $purchaseId,
            'ingredient_id' => $ingredient->id,
            'quantity' => 10,
            'unit_cost' => 2.5000,
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'purchase',
            'quantity' => 10,
            'reference_type' => Purchase::class,
            'reference_id' => $purchaseId,
            'created_by' => $user->id,
        ]);

        $ingredient->refresh();

        $this->assertEquals('10.000', $ingredient->current_stock);
    }

    public function test_purchase_defaults_to_users_primary_branch_when_branch_is_omitted(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredient = $this->createIngredient($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 5,
                        'unit_cost' => 1.25,
                    ],
                ],
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('data.branch_id', $branch->id);
    }

    public function test_manager_can_use_global_supplier(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier(null, 'Global Supplier');
        $ingredient = $this->createIngredient($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 3,
                        'unit_cost' => 4,
                    ],
                ],
            ]);

        $response->assertStatus(201);
    }

    public function test_manager_cannot_create_purchase_for_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($otherBranch->id);
        $ingredient = $this->createIngredient($otherBranch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $otherBranch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 5,
                        'unit_cost' => 2,
                    ],
                ],
            ]);

        $response->assertStatus(403);

        $this->assertDatabaseCount('purchases', 0);
    }

    public function test_manager_cannot_use_supplier_from_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($otherBranch->id);
        $ingredient = $this->createIngredient($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 5,
                        'unit_cost' => 2,
                    ],
                ],
            ]);

        $response->assertStatus(422);

        $this->assertDatabaseCount('purchases', 0);
    }

    public function test_purchase_rejects_ingredient_from_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredient = $this->createIngredient($otherBranch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 5,
                        'unit_cost' => 2,
                    ],
                ],
            ]);

        $response->assertStatus(422);

        $this->assertDatabaseCount('purchases', 0);
    }

    public function test_purchase_total_is_calculated_from_all_items(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredientOne = $this->createIngredient($branch, 'Coffee Beans');
        $ingredientTwo = $this->createIngredient($branch, 'Milk');

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'total_cost' => 999999,
                'items' => [
                    [
                        'ingredient_id' => $ingredientOne->id,
                        'quantity' => 10,
                        'unit_cost' => 2.50,
                    ],
                    [
                        'ingredient_id' => $ingredientTwo->id,
                        'quantity' => 4,
                        'unit_cost' => 3.75,
                    ],
                ],
            ]);

        $response->assertStatus(201)
            ->assertJsonPath('data.total_cost', '40.00');
    }

    public function test_purchase_validation_rejects_empty_items(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [],
            ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_purchase_validation_rejects_non_positive_quantity(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredient = $this->createIngredient($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/purchases', [
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'purchased_at' => '2026-09-17 00:00:00',
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity' => 0,
                        'unit_cost' => 2,
                    ],
                ],
            ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_manager_can_list_purchase_history_with_supplier_and_items(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $ingredient = $this->createIngredient($branch);

        $purchase = Purchase::create([
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'created_by' => $user->id,
            'total_cost' => 25.00,
            'purchased_at' => '2026-09-17 00:00:00',
        ]);

        $purchase->items()->create([
            'ingredient_id' => $ingredient->id,
            'quantity' => 10,
            'unit_cost' => 2.50,
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/purchases');

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.0.id', $purchase->id)
            ->assertJsonPath('data.0.branch_id', $branch->id)
            ->assertJsonPath('data.0.supplier.id', $supplier->id)
            ->assertJsonPath('data.0.supplier.name', $supplier->name)
            ->assertJsonPath('data.0.items.0.ingredient.id', $ingredient->id)
            ->assertJsonPath('data.0.items.0.ingredient.name', $ingredient->name)
            ->assertJsonPath('data.0.items.0.quantity', '10.000')
            ->assertJsonPath('data.0.items.0.unit_cost', '2.5000');

        $response->assertJsonStructure([
            'success',
            'data',
            'meta' => [
                'current_page',
                'last_page',
                'per_page',
                'total',
            ],
        ]);
    }

    public function test_purchase_history_defaults_to_users_primary_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);
        $otherSupplier = $this->createSupplier($otherBranch->id);

        $branchPurchase = Purchase::create([
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'created_by' => $user->id,
            'total_cost' => 10,
            'purchased_at' => '2026-09-17 00:00:00',
        ]);

        Purchase::create([
            'branch_id' => $otherBranch->id,
            'supplier_id' => $otherSupplier->id,
            'created_by' => $user->id,
            'total_cost' => 20,
            'purchased_at' => '2026-09-18',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/purchases');

        $response->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $branchPurchase->id);
    }

    public function test_purchase_history_rejects_another_branch(): void
    {
        $branch = Branch::factory()->create();
        $otherBranch = Branch::factory()->create();

        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($otherBranch->id);

        Purchase::create([
            'branch_id' => $otherBranch->id,
            'supplier_id' => $supplier->id,
            'created_by' => $user->id,
            'total_cost' => 20,
            'purchased_at' => '2026-09-17 00:00:00',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/purchases?branch_id=' . $otherBranch->id);

        $response->assertStatus(403);
    }

    public function test_purchase_history_supports_pagination(): void
    {
        $branch = Branch::factory()->create();
        $user = $this->makeUser($branch);
        $supplier = $this->createSupplier($branch->id);

        for ($i = 1; $i <= 3; $i++) {
            Purchase::create([
                'branch_id' => $branch->id,
                'supplier_id' => $supplier->id,
                'created_by' => $user->id,
                'total_cost' => $i * 10,
                'purchased_at' => '2026-09-' . str_pad((string) $i, 2, '0', STR_PAD_LEFT),
            ]);
        }

        $response = $this->actingAs($user)
            ->getJson('/api/v1/purchases?per_page=2');

        $response->assertOk()
            ->assertJsonPath('meta.per_page', 2)
            ->assertJsonPath('meta.total', 3)
            ->assertJsonPath('meta.current_page', 1)
            ->assertJsonPath('meta.last_page', 2)
            ->assertJsonCount(2, 'data');
    }

    public function test_unauthenticated_purchase_history_request_is_rejected(): void
    {
        $response = $this->getJson('/api/v1/purchases');

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

        $user->removeRole('manager');

        $response = $this->actingAs($user)
            ->getJson('/api/v1/purchases');

        $response->assertStatus(403);
    }
}
