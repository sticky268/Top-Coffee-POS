<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ProductManagementTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach (['products.manage', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }

        $manager = Role::firstOrCreate(['name' => 'manager', 'guard_name' => 'web']);
        $manager->syncPermissions(['products.manage']);

        $admin = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $admin->syncPermissions(['products.manage', 'branches.view-all']);

        // Deliberately no 'products.manage' synced here — matches the
        // real RolePermissionSeeder, and is used by the
        // permission-rejection tests below.
        Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
    }

    private function makeManager(Branch $branch): User
    {
        $this->seedPermissions();
        $user = User::factory()->create();
        $user->assignRole('manager');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    private function makeCashier(Branch $branch): User
    {
        $this->seedPermissions();
        $user = User::factory()->create();
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    // --- store() ---------------------------------------------------------

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->postJson('/api/v1/products', [])->assertStatus(401);
    }

    public function test_authorized_user_can_create_a_product(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $response = $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'sku' => 'COF-LATTE',
            'base_price' => 3.50,
        ]);

        $response->assertStatus(201)->assertJsonPath('success', true);
        $response->assertJsonPath('data.name', 'Iced Latte');
        $response->assertJsonPath('data.base_price', 3.5);
        $response->assertJsonPath('data.is_active', true);
    }

    public function test_created_product_is_saved_in_the_database(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
        ]);

        $this->assertDatabaseHas('products', ['name' => 'Iced Latte', 'base_price' => 3.50]);
    }

    public function test_created_product_appears_in_the_products_listing(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $create = $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
            'branches' => [
                ['branch_id' => $branch->id, 'is_available' => true],
            ],
        ]);
        $create->assertStatus(201);

        $listing = $this->actingAs($manager)->getJson('/api/v1/products');
        $this->assertTrue(collect($listing->json('data'))->pluck('name')->contains('Iced Latte'));
    }

    public function test_unauthorized_user_cannot_create_a_product(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $response = $this->actingAs($cashier)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
        $this->assertDatabaseMissing('products', ['name' => 'Iced Latte']);
    }

    public function test_invalid_product_data_returns_validation_errors(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);

        $response = $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => '',
            'category_id' => 999999, // doesn't exist
            'base_price' => -5, // invalid
        ]);

        $response->assertStatus(422)->assertJsonPath('success', false);
        $response->assertJsonValidationErrors(['name', 'category_id', 'base_price']);
    }

    public function test_a_branch_restricted_manager_cannot_assign_availability_to_another_branch(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $response = $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
            'branches' => [
                ['branch_id' => $otherBranch->id, 'is_available' => true],
            ],
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
        $this->assertDatabaseMissing('products', ['name' => 'Iced Latte']);
    }

    public function test_admin_with_view_all_can_assign_availability_to_any_branch(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $this->seedPermissions();
        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $response = $this->actingAs($admin)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
            'branches' => [
                ['branch_id' => $otherBranch->id, 'is_available' => true],
            ],
        ]);

        $response->assertStatus(201);
    }

    public function test_variants_and_branch_pricing_are_created_with_the_product(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $response = $this->actingAs($manager)->postJson('/api/v1/products', [
            'name' => 'Iced Latte',
            'category_id' => $category->id,
            'base_price' => 3.50,
            'variants' => [
                ['name' => 'Large', 'price_delta' => 0.75],
            ],
            'branches' => [
                ['branch_id' => $branch->id, 'price_override' => 3.00, 'is_available' => true],
            ],
        ]);

        $response->assertStatus(201);
        $response->assertJsonCount(1, 'data.variants');
        $response->assertJsonPath('data.variants.0.name', 'Large');
        $this->assertEquals(
            3.0,
            (float) $response->json('data.branches.0.price_override')
        );
    }

    // --- update() --------------------------------------------------------

    public function test_authorized_user_can_update_a_product(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);

        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'name' => 'Iced Latte',
            'base_price' => 3.75,
        ]);

        $response->assertStatus(200)->assertJsonPath('success', true);
        $response->assertJsonPath('data.name', 'Iced Latte');
        $this->assertDatabaseHas('products', ['id' => $product->id, 'name' => 'Iced Latte', 'base_price' => 3.75]);
    }

    public function test_unauthorized_user_cannot_update_a_product(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);

        $response = $this->actingAs($cashier)->patchJson("/api/v1/products/{$product->id}", [
            'name' => 'Hacked Name',
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
        $this->assertDatabaseHas('products', ['id' => $product->id, 'name' => 'Latte']);
    }

    public function test_product_can_be_safely_disabled_via_is_active(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'is_active' => false,
        ]);

        $response->assertStatus(200)->assertJsonPath('data.is_active', false);

        // Still physically present — never hard-deleted.
        $this->assertDatabaseHas('products', ['id' => $product->id, 'name' => 'Latte']);

        // Disabled products disappear from the customer-facing catalog
        // (existing, unmodified index() behavior — is_active filter).
        $listing = $this->actingAs($manager)->getJson('/api/v1/products');
        $this->assertFalse(collect($listing->json('data'))->pluck('name')->contains('Latte'));
    }

    public function test_updating_variants_upserts_without_deleting_omitted_ones(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $existingVariant = ProductVariant::create([
            'product_id' => $product->id, 'name' => 'Small', 'price_delta' => -0.25,
        ]);

        // Update only mentions a NEW variant — "Small" is not in the
        // payload at all, and must survive untouched.
        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [
                ['name' => 'Large', 'price_delta' => 0.75],
            ],
        ]);

        $response->assertStatus(200);
        $this->assertDatabaseHas('product_variants', ['id' => $existingVariant->id, 'name' => 'Small']);
        $this->assertDatabaseHas('product_variants', ['product_id' => $product->id, 'name' => 'Large']);
        $this->assertEquals(2, ProductVariant::where('product_id', $product->id)->count());
    }

    public function test_updating_a_variant_by_id_modifies_it_in_place(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $variant = ProductVariant::create(['product_id' => $product->id, 'name' => 'Large', 'price_delta' => 0.75]);

        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [
                ['id' => $variant->id, 'name' => 'Extra Large', 'price_delta' => 1.00],
            ],
        ]);

        $response->assertStatus(200);
        $this->assertEquals(1, ProductVariant::where('product_id', $product->id)->count());
        $this->assertDatabaseHas('product_variants', ['id' => $variant->id, 'name' => 'Extra Large', 'price_delta' => 1.00]);
    }

    public function test_branch_update_does_not_wipe_out_another_branchs_availability(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $this->seedPermissions();
        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        $product->branches()->attach($otherBranch->id, ['is_available' => true]);

        // Admin updates only $branch's pricing — $otherBranch is not
        // mentioned at all.
        $response = $this->actingAs($admin)->patchJson("/api/v1/products/{$product->id}", [
            'branches' => [
                ['branch_id' => $branch->id, 'price_override' => 3.25, 'is_available' => true],
            ],
        ]);

        $response->assertStatus(200);
        // otherBranch's pivot row must still exist, untouched.
        $this->assertDatabaseHas('branch_product', [
            'branch_id' => $otherBranch->id, 'product_id' => $product->id, 'is_available' => 1,
        ]);
    }

    public function test_a_branch_restricted_manager_cannot_update_availability_for_another_branch(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);

        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'branches' => [
                ['branch_id' => $otherBranch->id, 'is_available' => true],
            ],
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_updating_a_nonexistent_product_returns_404(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);

        $response = $this->actingAs($manager)->patchJson('/api/v1/products/999999', ['name' => 'X']);

        $response->assertStatus(404);
    }

    public function test_sku_uniqueness_ignores_the_products_own_current_sku_on_update(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create([
            'category_id' => $category->id, 'name' => 'Latte', 'sku' => 'COF-LATTE', 'base_price' => 3.50,
        ]);

        // Re-submitting the product's own unchanged sku must not trigger
        // a false "already taken" validation error.
        $response = $this->actingAs($manager)->patchJson("/api/v1/products/{$product->id}", [
            'sku' => 'COF-LATTE',
            'base_price' => 3.75,
        ]);

        $response->assertStatus(200);
    }

    // --- existing listing tests still pass (sanity re-check) --------------

    public function test_existing_product_listing_behavior_is_unaffected(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $manager = $this->makeManager($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true, 'price_override' => 3.00]);

        $response = $this->actingAs($manager)->getJson('/api/v1/products');

        $response->assertStatus(200)->assertJsonPath('success', true);
        $productJson = collect($response->json('data'))->firstWhere('name', 'Latte');
        $this->assertEquals(3.00, $productJson['price']);
    }
}
