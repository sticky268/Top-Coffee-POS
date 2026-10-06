<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Ingredient;
use App\Models\Product;
use App\Models\RecipeItem;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class IngredientManagementTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach ([
            'inventory.manage',
            'inventory.adjust',
            'products.manage',
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
            'inventory.adjust',
            'products.manage',
        ]);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);

        $admin->syncPermissions([
            'inventory.manage',
            'inventory.adjust',
            'products.manage',
            'branches.view-all',
        ]);

        Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ]);
    }

    private function makeManager(Branch $branch): User
    {
        $this->seedPermissions();

        $user = User::factory()->create();
        $user->assignRole('manager');

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    private function makeCashier(Branch $branch): User
    {
        $this->seedPermissions();

        $user = User::factory()->create();
        $user->assignRole('cashier');

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    private function createUnit(
        string $name = 'Gram',
        string $abbreviation = 'g',
    ): int {
        return DB::table('units')->insertGetId([
            'name' => $name,
            'abbreviation' => $abbreviation,
            'base_unit_id' => null,
            'conversion_factor' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function createIngredient(
        Branch $branch,
        int $unitId,
        string $name = 'Coffee',
        float $stock = 100,
    ): Ingredient {
        $ingredient = Ingredient::create([
            'branch_id' => $branch->id,
            'unit_id' => $unitId,
            'name' => $name,
            'reorder_threshold' => 10,
            'is_active' => true,
        ]);

        DB::table('ingredients')
            ->where('id', $ingredient->id)
            ->update([
                'current_stock' => $stock,
            ]);

        return $ingredient->refresh();
    }

    private function createProduct(): Product
    {
        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
            'sort_order' => 1,
            'is_active' => true,
        ]);

        return Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'sku' => 'ICED-LATTE',
            'description' => null,
            'base_price' => 3.50,
            'is_active' => true,
        ]);
    }

    public function test_manager_can_update_ingredient_without_changing_current_stock(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
            name: 'Old Coffee',
            stock: 100,
        );

        $response = $this
            ->actingAs($manager)
            ->patchJson("/api/v1/ingredients/{$ingredient->id}", [
                'name' => 'Premium Coffee',
                'unit_id' => $unitId,
                'reorder_threshold' => 25,
                'is_active' => false,
            ]);

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $ingredient->id)
            ->assertJsonPath('data.name', 'Premium Coffee')
            ->assertJsonPath('data.reorder_threshold', '25.000')
            ->assertJsonPath('data.is_active', false)
            ->assertJsonPath('data.current_stock', '100.000');

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'name' => 'Premium Coffee',
            'unit_id' => $unitId,
            'current_stock' => 100,
            'reorder_threshold' => 25,
            'is_active' => false,
        ]);
    }

    public function test_cashier_cannot_update_ingredient(): void
    {
        $branch = Branch::factory()->create();
        $cashier = $this->makeCashier($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($cashier)
            ->patchJson("/api/v1/ingredients/{$ingredient->id}", [
                'name' => 'Changed Coffee',
                'unit_id' => $unitId,
                'reorder_threshold' => 20,
                'is_active' => true,
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'name' => 'Coffee',
            'current_stock' => 100,
            'reorder_threshold' => 10,
            'is_active' => true,
        ]);
    }

    public function test_manager_can_change_unit_when_ingredient_has_not_been_used(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $gramUnitId = $this->createUnit('Gram', 'g');
        $milliliterUnitId = $this->createUnit('Milliliter', 'ml');

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $gramUnitId,
        );

        $response = $this
            ->actingAs($manager)
            ->patchJson("/api/v1/ingredients/{$ingredient->id}", [
                'name' => 'Coffee',
                'unit_id' => $milliliterUnitId,
                'reorder_threshold' => 10,
                'is_active' => true,
            ]);

        $response
            ->assertOk()
            ->assertJsonPath('data.unit.id', $milliliterUnitId)
            ->assertJsonPath('data.unit.abbreviation', 'ml');

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'unit_id' => $milliliterUnitId,
        ]);
    }

    public function test_unit_change_is_rejected_after_stock_movement(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $gramUnitId = $this->createUnit('Gram', 'g');
        $milliliterUnitId = $this->createUnit('Milliliter', 'ml');

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $gramUnitId,
        );

        DB::table('stock_movements')->insert([
            'branch_id' => $branch->id,
            'ingredient_id' => $ingredient->id,
            'created_by' => $manager->id,
            'type' => 'purchase',
            'quantity' => 10,
            'balance_after' => 110,
            'reason' => 'Initial stock',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $response = $this
            ->actingAs($manager)
            ->patchJson("/api/v1/ingredients/{$ingredient->id}", [
                'name' => 'Coffee',
                'unit_id' => $milliliterUnitId,
                'reorder_threshold' => 10,
                'is_active' => true,
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'unit_id' => $gramUnitId,
        ]);
    }

    public function test_manager_can_soft_delete_unused_ingredient(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
            name: 'Test Ingredient',
        );

        $response = $this
            ->actingAs($manager)
            ->deleteJson("/api/v1/ingredients/{$ingredient->id}");

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Ingredient deleted successfully.');

        $this->assertSoftDeleted('ingredients', [
            'id' => $ingredient->id,
        ]);
    }

    public function test_manager_can_soft_delete_ingredient_with_stock_movements_while_preserving_history(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        DB::table('stock_movements')->insert([
            'branch_id' => $branch->id,
            'ingredient_id' => $ingredient->id,
            'created_by' => $manager->id,
            'type' => 'purchase',
            'quantity' => 10,
            'balance_after' => 110,
            'reason' => 'Initial stock',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $response = $this
            ->actingAs($manager)
            ->deleteJson("/api/v1/ingredients/{$ingredient->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath(
                'message',
                'Ingredient deleted successfully.'
            );

        $this->assertSoftDeleted('ingredients', [
            'id' => $ingredient->id,
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'purchase',
            'quantity' => 10,
            'balance_after' => 110,
            'reason' => 'Initial stock',
            'created_by' => $manager->id,
        ]);
    }

    public function test_ingredient_used_in_recipe_cannot_be_deleted(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $product = $this->createProduct();

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $ingredient->id,
            'quantity_used' => 18,
        ]);

        $response = $this
            ->actingAs($manager)
            ->deleteJson("/api/v1/ingredients/{$ingredient->id}");

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'deleted_at' => null,
        ]);
    }

    public function test_cashier_cannot_delete_ingredient(): void
    {
        $branch = Branch::factory()->create();
        $cashier = $this->makeCashier($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($cashier)
            ->deleteJson("/api/v1/ingredients/{$ingredient->id}");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'deleted_at' => null,
        ]);
    }

    public function test_deleting_nonexistent_ingredient_returns_not_found(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $response = $this
            ->actingAs($manager)
            ->deleteJson('/api/v1/ingredients/999999');

        $response
            ->assertStatus(404)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Ingredient not found.');
    }
    public function test_unit_change_is_rejected_after_recipe_usage(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $gramUnitId = $this->createUnit('Gram', 'g');
        $milliliterUnitId = $this->createUnit('Milliliter', 'ml');

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $gramUnitId,
        );

        $product = $this->createProduct();

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $ingredient->id,
            'quantity_used' => 18,
        ]);

        $response = $this
            ->actingAs($manager)
            ->patchJson("/api/v1/ingredients/{$ingredient->id}", [
                'name' => 'Coffee',
                'unit_id' => $milliliterUnitId,
                'reorder_threshold' => 10,
                'is_active' => true,
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('ingredients', [
            'id' => $ingredient->id,
            'unit_id' => $gramUnitId,
        ]);
    }

    public function test_deleted_ingredient_cannot_receive_manual_adjustment(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $ingredient->delete();

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'adjustment',
                'quantity' => 10,
                'reason' => 'Manual correction',
            ]);

        $response
            ->assertStatus(404)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Ingredient not found.');

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }

    public function test_manager_can_record_purchase_stock_movement(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'purchase',
                'quantity' => 25,
                'reason' => 'Supplier delivery',
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.movement.type', 'purchase');

        $this->assertSame(
            125.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'purchase',
            'quantity' => 25,
            'balance_after' => 125,
            'created_by' => $manager->id,
        ]);
    }

    public function test_manager_can_record_wastage_stock_movement(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'wastage',
                'quantity' => 15,
                'reason' => 'Damaged stock',
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.movement.type', 'wastage');

        $this->assertSame(
            85.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'wastage',
            'quantity' => -15,
            'balance_after' => 85,
            'reason' => 'Damaged stock',
            'created_by' => $manager->id,
        ]);
    }

    public function test_wastage_requires_reason(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'wastage',
                'quantity' => 15,
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath(
                'message',
                'A reason is required for adjustment and wastage movements.',
            );

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }

    public function test_wastage_cannot_reduce_stock_below_zero(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
            stock: 10,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'wastage',
                'quantity' => 15,
                'reason' => 'Damaged stock',
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath(
                'message',
                'Stock cannot be reduced below zero.',
            );

        $this->assertSame(
            10.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }


    public function test_manager_can_record_positive_adjustment(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'adjustment',
                'quantity' => 20,
                'reason' => 'Stock count correction',
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.movement.type', 'adjustment');

        $this->assertSame(
            120.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'adjustment',
            'quantity' => 20,
            'balance_after' => 120,
            'reason' => 'Stock count correction',
            'created_by' => $manager->id,
        ]);
    }

    public function test_manager_can_record_negative_adjustment(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'adjustment',
                'quantity' => -20,
                'reason' => 'Stock count correction',
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.movement.type', 'adjustment');

        $this->assertSame(
            80.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $ingredient->id,
            'branch_id' => $branch->id,
            'type' => 'adjustment',
            'quantity' => -20,
            'balance_after' => 80,
            'reason' => 'Stock count correction',
            'created_by' => $manager->id,
        ]);
    }

    public function test_adjustment_cannot_reduce_stock_below_zero(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
            stock: 10,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'adjustment',
                'quantity' => -15,
                'reason' => 'Stock count correction',
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath(
                'message',
                'Stock cannot be reduced below zero.',
            );

        $this->assertSame(
            10.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }

    public function test_purchase_quantity_must_be_positive(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'purchase',
                'quantity' => -10,
                'reason' => 'Invalid purchase',
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath(
                'message',
                'Purchase quantity must be positive.',
            );

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }

    public function test_stock_movement_quantity_cannot_be_zero(): void
    {
        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'adjustment',
                'quantity' => 0,
                'reason' => 'Zero movement',
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Validation failed.')
            ->assertJsonPath(
                'errors.quantity.0',
                'The selected quantity is invalid.',
            );

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }


    public function test_user_without_inventory_adjust_cannot_record_stock_movement(): void
    {
        $branch = Branch::factory()->create();
        $cashier = $this->makeCashier($branch);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($cashier)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'purchase',
                'quantity' => 25,
                'reason' => 'Unauthorized purchase',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Forbidden');

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }

    public function test_manager_cannot_record_stock_movement_for_another_branch(): void
    {
        $branchA = Branch::factory()->create([
            'name' => 'Branch A',
            'code' => 'A-01',
        ]);

        $branchB = Branch::factory()->create([
            'name' => 'Branch B',
            'code' => 'B-01',
        ]);

        $manager = $this->makeManager($branchA);

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branchB,
            unitId: $unitId,
        );

        $response = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'purchase',
                'quantity' => 25,
                'reason' => 'Cross-branch purchase',
            ]);

        $response
            ->assertStatus(404)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Ingredient not found.');

        $this->assertSame(
            100.0,
            (float) $ingredient->fresh()->current_stock,
        );

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $ingredient->id,
        ]);
    }


    public function test_manager_can_view_ingredient_movement_history(): void
    {
        $this->seedPermissions();

        $branch = Branch::factory()->create();
        $manager = $this->makeManager($branch);

        Permission::firstOrCreate([
            'name' => 'inventory.view',
            'guard_name' => 'web',
        ]);

        $manager->givePermissionTo('inventory.view');

        $unitId = $this->createUnit();

        $ingredient = $this->createIngredient(
            branch: $branch,
            unitId: $unitId,
        );

        $purchaseResponse = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'purchase',
                'quantity' => 20,
                'reason' => 'Supplier delivery',
            ]);

        $purchaseResponse->assertStatus(201);

        $wastageResponse = $this
            ->actingAs($manager)
            ->postJson("/api/v1/ingredients/{$ingredient->id}/movements", [
                'type' => 'wastage',
                'quantity' => 5,
                'reason' => 'Damaged stock',
            ]);

        $wastageResponse->assertStatus(201);

        $response = $this
            ->actingAs($manager)
            ->getJson("/api/v1/ingredients/{$ingredient->id}/movements");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('ingredient.id', $ingredient->id)
            ->assertJsonPath('ingredient.current_stock', '115.000')
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.type', 'wastage')
            ->assertJsonPath('data.0.quantity', '-5.000')
            ->assertJsonPath('data.0.reason', 'Damaged stock')
            ->assertJsonPath('data.1.type', 'purchase')
            ->assertJsonPath('data.1.quantity', '20.000')
            ->assertJsonPath('meta.total', 2);
    }

}