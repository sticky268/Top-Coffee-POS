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

        $movementId = DB::table('stock_movements')->insertGetId([
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
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Ingredient deleted successfully.');

        $this->assertSoftDeleted('ingredients', [
            'id' => $ingredient->id,
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'id' => $movementId,
            'ingredient_id' => $ingredient->id,
            'type' => 'purchase',
            'quantity' => 10,
            'balance_after' => 110,
            'reason' => 'Initial stock',
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
}