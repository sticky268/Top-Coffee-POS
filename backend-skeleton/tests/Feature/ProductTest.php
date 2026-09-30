<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ProductTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

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
        $this->getJson('/api/v1/products')->assertStatus(401);
    }

    public function test_only_returns_products_assigned_and_available_at_the_users_branch(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeUserForBranch($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $available = Product::create([
            'category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50,
        ]);
        $available->branches()->attach($branch->id, ['is_available' => true]);

        $unavailableAtBranch = Product::create([
            'category_id' => $category->id, 'name' => 'Espresso', 'base_price' => 2.50,
        ]);
        $unavailableAtBranch->branches()->attach($branch->id, ['is_available' => false]);

        $notAssignedToBranch = Product::create([
            'category_id' => $category->id, 'name' => 'Cold Brew', 'base_price' => 4.00,
        ]);
        $notAssignedToBranch->branches()->attach($otherBranch->id, ['is_available' => true]);

        $inactiveProduct = Product::create([
            'category_id' => $category->id, 'name' => 'Discontinued Mocha', 'base_price' => 3.00, 'is_active' => false,
        ]);
        $inactiveProduct->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->getJson('/api/v1/products');
        $response->assertStatus(200)->assertJsonPath('success', true);

        $names = collect($response->json('data'))->pluck('name');
        $this->assertTrue($names->contains('Latte'));
        $this->assertFalse($names->contains('Espresso'));
        $this->assertFalse($names->contains('Cold Brew'));
        $this->assertFalse($names->contains('Discontinued Mocha'));
    }

    public function test_uses_branch_price_override_when_set(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true, 'price_override' => 3.00]);

        $response = $this->actingAs($user)->getJson('/api/v1/products');

        $productJson = collect($response->json('data'))->firstWhere('name', 'Latte');
        $this->assertEquals(3.00, $productJson['price']);
    }

    public function test_falls_back_to_base_price_when_no_override_is_set(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->getJson('/api/v1/products');

        $productJson = collect($response->json('data'))->firstWhere('name', 'Latte');
        $this->assertEquals(3.50, $productJson['price']);
    }

    public function test_variant_prices_are_the_resolved_absolute_price_not_just_the_delta(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true, 'price_override' => 3.00]);
        ProductVariant::create(['product_id' => $product->id, 'name' => 'Large', 'price_delta' => 0.75]);
        ProductVariant::create(['product_id' => $product->id, 'name' => 'Small', 'price_delta' => 0, 'is_active' => false]);

        $response = $this->actingAs($user)->getJson('/api/v1/products');

        $productJson = collect($response->json('data'))->firstWhere('name', 'Latte');
        $this->assertCount(1, $productJson['variants']); // inactive variant excluded
        $this->assertEquals('Large', $productJson['variants'][0]['name']);
        $this->assertEquals(3.75, $productJson['variants'][0]['price']); // 3.00 override + 0.75 delta
    }

    public function test_category_id_filter_narrows_results(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        $coffee = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $tea = Category::create(['branch_id' => null, 'name' => 'Tea']);

        $latte = Product::create(['category_id' => $coffee->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $latte->branches()->attach($branch->id, ['is_available' => true]);

        $greenTea = Product::create(['category_id' => $tea->id, 'name' => 'Green Tea', 'base_price' => 2.50]);
        $greenTea->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->getJson("/api/v1/products?category_id={$coffee->id}");

        $names = collect($response->json('data'))->pluck('name');
        $this->assertTrue($names->contains('Latte'));
        $this->assertFalse($names->contains('Green Tea'));
    }

    public function test_category_info_is_included_on_each_product(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeUserForBranch($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->getJson('/api/v1/products');

        $productJson = collect($response->json('data'))->firstWhere('name', 'Latte');
        $this->assertEquals($category->id, $productJson['category']['id']);
        $this->assertEquals('Coffee', $productJson['category']['name']);
    }

    public function test_explicit_branch_id_for_an_unassigned_branch_is_rejected(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)->getJson("/api/v1/products?branch_id={$otherBranch->id}");

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_admin_with_view_all_permission_can_request_any_branch(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'BKK1', 'code' => 'PP-02']);

        Permission::firstOrCreate(['name' => 'branches.view-all', 'guard_name' => 'web']);
        $adminRole = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $adminRole->syncPermissions(['branches.view-all']);

        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $product->branches()->attach($otherBranch->id, ['is_available' => true]);

        $response = $this->actingAs($admin)->getJson("/api/v1/products?branch_id={$otherBranch->id}");

        $response->assertStatus(200)->assertJsonPath('success', true);
        $this->assertTrue(collect($response->json('data'))->pluck('name')->contains('Latte'));
    }
}
