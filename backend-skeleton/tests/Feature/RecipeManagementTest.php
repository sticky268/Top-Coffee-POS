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

class RecipeManagementTest extends TestCase
{
    use RefreshDatabase;

    private \App\Models\Business $business;

    protected function setUp(): void
    {
        parent::setUp();
        $this->business = \App\Models\Business::factory()->create();
    }

    private function seedPermissions(): void
    {
        foreach (['products.manage', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        $manager = Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);
        $manager->syncPermissions(['products.manage']);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);
        $admin->syncPermissions([
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

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole('manager');
        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    private function makeCashier(Branch $branch): User
    {
        $this->seedPermissions();

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
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

    private function createIngredient(
        Branch $branch,
        int $unitId,
        string $name,
        float $stock = 100,
    ): Ingredient {
        return Ingredient::create([
            'branch_id' => $branch->id,
            'unit_id' => $unitId,
            'name' => $name,
            'current_stock' => $stock,
            'reorder_threshold' => 10,
            'is_active' => true,
        ]);
    }

    private function createProduct(string $name = 'Iced Latte'): Product
    {
        $category = Category::forceCreate(['business_id' => $this->business->id,
            'branch_id' => null,
            'name' => 'Coffee',
            'sort_order' => 1,
            'is_active' => true,
        ]);

        return Product::create([
            'category_id' => $category->id,
            'name' => $name,
            'sku' => strtoupper(str_replace(' ', '-', $name)),
            'description' => null,
            'base_price' => 3.50,
            'is_active' => true,
        ]);
    }

    public function test_manager_can_create_and_retrieve_product_recipe(): void
    {
        $branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
        );

        $product = $this->createProduct();

        $response = $this
            ->actingAs($manager)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branch->id,
                'items' => [
                    [
                        'ingredient_id' => $coffee->id,
                        'quantity_used' => 18,
                    ],
                    [
                        'ingredient_id' => $milk->id,
                        'quantity_used' => 250,
                    ],
                ],
            ]);

        $response
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.branch_id', $branch->id)
            ->assertJsonCount(2, 'data.items');

        $this->assertDatabaseHas('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        $this->assertDatabaseHas('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $getResponse = $this
            ->actingAs($manager)
            ->getJson("/api/v1/products/{$product->id}/recipe?branch_id={$branch->id}");

        $getResponse
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.branch_id', $branch->id)
            ->assertJsonCount(2, 'data.items');
    }

    public function test_cashier_cannot_update_product_recipe(): void
    {
        $branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $cashier = $this->makeCashier($branch);

        $unitId = $this->createUnit();
        $ingredient = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
        );

        $product = $this->createProduct();

        $response = $this
            ->actingAs($cashier)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branch->id,
                'items' => [
                    [
                        'ingredient_id' => $ingredient->id,
                        'quantity_used' => 18,
                    ],
                ],
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseCount('recipe_items', 0);
    }

    public function test_recipe_rejects_ingredient_from_another_branch(): void
    {
        $branchOne = Branch::factory()->create(['business_id' => $this->business->id]);
        $branchTwo = Branch::factory()->create(['business_id' => $this->business->id]);

        $manager = $this->makeManager($branchOne);

        $unitId = $this->createUnit();

        $foreignIngredient = $this->createIngredient(
            $branchTwo,
            $unitId,
            'Branch Two Coffee',
        );

        $product = $this->createProduct();

        $response = $this
            ->actingAs($manager)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branchOne->id,
                'items' => [
                    [
                        'ingredient_id' => $foreignIngredient->id,
                        'quantity_used' => 18,
                    ],
                ],
            ]);

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseCount('recipe_items', 0);
    }

    public function test_recipe_is_isolated_between_branches(): void
    {
        $branchOne = Branch::factory()->create(['business_id' => $this->business->id]);
        $branchTwo = Branch::factory()->create(['business_id' => $this->business->id]);

        $managerOne = $this->makeManager($branchOne);
        $managerTwo = $this->makeManager($branchTwo);

        $unitId = $this->createUnit();

        $coffeeOne = $this->createIngredient(
            $branchOne,
            $unitId,
            'Branch One Coffee',
        );

        $coffeeTwo = $this->createIngredient(
            $branchTwo,
            $unitId,
            'Branch Two Coffee',
        );

        $product = $this->createProduct();

        $this
            ->actingAs($managerOne)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branchOne->id,
                'items' => [
                    [
                        'ingredient_id' => $coffeeOne->id,
                        'quantity_used' => 18,
                    ],
                ],
            ])
            ->assertOk();

        $this
            ->actingAs($managerTwo)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branchTwo->id,
                'items' => [
                    [
                        'ingredient_id' => $coffeeTwo->id,
                        'quantity_used' => 20,
                    ],
                ],
            ])
            ->assertOk();

        $branchOneResponse = $this
            ->actingAs($managerOne)
            ->getJson("/api/v1/products/{$product->id}/recipe?branch_id={$branchOne->id}");

        $branchOneResponse
            ->assertOk()
            ->assertJsonPath('data.branch_id', $branchOne->id)
            ->assertJsonPath('data.items.0.ingredient_id', $coffeeOne->id)
            ->assertJsonPath('data.items.0.quantity_used', '18.000');

        $branchTwoResponse = $this
            ->actingAs($managerTwo)
            ->getJson("/api/v1/products/{$product->id}/recipe?branch_id={$branchTwo->id}");

        $branchTwoResponse
            ->assertOk()
            ->assertJsonPath('data.branch_id', $branchTwo->id)
            ->assertJsonPath('data.items.0.ingredient_id', $coffeeTwo->id)
            ->assertJsonPath('data.items.0.quantity_used', '20.000');
    }

    public function test_updating_recipe_replaces_existing_items(): void
    {
        $branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $manager = $this->makeManager($branch);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
        );

        $syrup = $this->createIngredient(
            $branch,
            $unitId,
            'Vanilla Syrup',
        );

        $product = $this->createProduct();

        $this
            ->actingAs($manager)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branch->id,
                'items' => [
                    [
                        'ingredient_id' => $coffee->id,
                        'quantity_used' => 18,
                    ],
                    [
                        'ingredient_id' => $milk->id,
                        'quantity_used' => 250,
                    ],
                ],
            ])
            ->assertOk();

        $this
            ->actingAs($manager)
            ->putJson("/api/v1/products/{$product->id}/recipe", [
                'branch_id' => $branch->id,
                'items' => [
                    [
                        'ingredient_id' => $coffee->id,
                        'quantity_used' => 20,
                    ],
                    [
                        'ingredient_id' => $milk->id,
                        'quantity_used' => 300,
                    ],
                    [
                        'ingredient_id' => $syrup->id,
                        'quantity_used' => 15,
                    ],
                ],
            ])
            ->assertOk()
            ->assertJsonCount(3, 'data.items');

        $this->assertDatabaseMissing('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        $this->assertDatabaseHas('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 20,
        ]);

        $this->assertDatabaseHas('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $milk->id,
            'quantity_used' => 300,
        ]);

        $this->assertDatabaseHas('recipe_items', [
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $syrup->id,
            'quantity_used' => 15,
        ]);

        $this->assertDatabaseCount('recipe_items', 3);
    }
}