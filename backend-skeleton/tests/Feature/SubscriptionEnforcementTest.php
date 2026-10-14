<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Category;
use App\Models\Customer;
use App\Models\Plan;
use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class SubscriptionEnforcementTest extends TestCase
{
    use RefreshDatabase;

    private function createPlan(int $branchLimit = 1): Plan
    {
        return Plan::factory()->create([
            'branch_limit' => $branchLimit,
            'is_active' => true,
        ]);
    }

    private function createBusiness(array $attributes = []): Business
    {
        $plan = $this->createPlan();

        return Business::factory()->create(array_merge([
            'plan_id' => $plan->id,
            'status' => 'trial',
            'expires_at' => null,
        ], $attributes));
    }

    private function createUserForBusiness(Business $business): User
    {
        return User::factory()->create([
            'business_id' => $business->id,
        ]);
    }

    private function createCustomerManageUser(Business $business): User
    {
        Permission::firstOrCreate([
            'name' => 'customers.manage',
            'guard_name' => 'web',
        ]);

        Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ])->syncPermissions(['customers.manage']);

        $user = $this->createUserForBusiness($business);
        $user->assignRole('cashier');

        return $user;
    }

    public function test_expired_business_cannot_create_customer(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)->postJson('/api/v1/customers', [
            'name' => 'Expired Customer',
            'phone' => '012345678',
        ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'SUBSCRIPTION_EXPIRED');
    }

    public function test_expired_business_cannot_create_order(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [],
        ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'SUBSCRIPTION_EXPIRED');
    }

    public function test_expired_business_cannot_create_product(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)->postJson('/api/v1/products', [
            'name' => 'Expired Product',
            'sku' => 'EXPIRED-001',
            'price' => 2.50,
        ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'SUBSCRIPTION_EXPIRED');
    }

    public function test_expired_business_cannot_create_branch(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)->postJson('/api/v1/branches', [
            'name' => 'Expired Branch',
            'code' => 'EXP-001',
            'timezone' => 'Asia/Phnom_Penh',
        ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'SUBSCRIPTION_EXPIRED');
    }

    public function test_expired_business_can_read_products(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $branch = Branch::create([
            'business_id' => $business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->createUserForBusiness($business);

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $category = Category::forceCreate([
            'business_id' => $business->id,
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/products');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertTrue(
            collect($response->json('data'))
                ->pluck('name')
                ->contains('Latte')
        );
    }

    public function test_suspended_business_cannot_modify_data(): void
    {
        $business = $this->createBusiness([
            'status' => 'suspended',
            'expires_at' => Carbon::now()->addMonth(),
        ]);

        $user = $this->createUserForBusiness($business);

        $response = $this->actingAs($user)->postJson('/api/v1/customers', [
            'name' => 'Suspended Customer',
            'phone' => '012345678',
        ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('code', 'BUSINESS_SUSPENDED');
    }

    public function test_active_business_can_modify_data(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->addMonth(),
        ]);

        $user = $this->createCustomerManageUser($business);

        $branch = Branch::create([
            'business_id' => $business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/customers', [
            'name' => 'Active Customer',
            'phone' => '012345678',
        ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true);

        $this->assertDatabaseHas('customers', [
            'name' => 'Active Customer',
            'branch_id' => $branch->id,
        ]);
    }

    public function test_expired_business_can_still_login(): void
    {
        $business = $this->createBusiness([
            'status' => 'active',
            'expires_at' => Carbon::now()->subDay(),
        ]);

        $user = User::factory()->create([
            'business_id' => $business->id,
            'password' => 'password',
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'subscription-test',
        ]);

        $response->assertSuccessful();
    }
}
