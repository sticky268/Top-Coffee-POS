<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Customer;
use App\Models\Order;
use App\Models\LoyaltyTransaction;
use App\Models\CustomerLoyaltyAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class CustomerTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

    private function createBranch(string $name, string $code): Branch
    {
        return Branch::create([
            'business_id' => $this->business->id,
            'name' => $name,
            'code' => $code,
        ]);
    }

    private function createCustomerOrder(
        Branch $branch,
        User $user,
        Customer $customer,
        string $status = 'completed'
    ): Order {
        return Order::create([
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branch->id,
            'user_id' => $user->id,
            'customer_id' => $customer->id,
            'order_type' => 'takeaway',
            'status' => $status,
            'subtotal' => 10.00,
            'discount_total' => 0,
            'tax_total' => 0,
            'total' => 10.00,
            'completed_at' => $status === 'completed' ? now() : null,
        ]);
    }
    private function makeUserForBranch(
        Branch $branch,
        string $role = 'cashier'
    ): User {
        Permission::firstOrCreate([
            'name' => 'customers.manage',
            'guard_name' => 'web',
        ]);

        Role::firstOrCreate([
            'name' => $role,
            'guard_name' => 'web',
        ])->syncPermissions(['customers.manage']);

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole($role);
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/customers')
            ->assertStatus(401);
    }

    public function test_returns_global_and_own_branch_customers_by_default(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => null,
            'name' => 'Global Customer',
        ]);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Own Branch Customer',
        ]);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Customer',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/customers');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $names = collect($response->json('data'))
            ->pluck('name');

        $this->assertTrue($names->contains('Global Customer'));
        $this->assertTrue($names->contains('Own Branch Customer'));
        $this->assertFalse($names->contains('Other Branch Customer'));
    }

    public function test_explicit_branch_id_for_assigned_branch_is_allowed(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Branch Customer',
        ]);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers?branch_id={$branch->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);
    }

    public function test_explicit_branch_id_for_unassigned_branch_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers?branch_id={$otherBranch->id}");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_admin_with_view_all_permission_can_request_any_branch(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        Permission::firstOrCreate([
            'name' => 'customers.manage',
            'guard_name' => 'web',
        ]);

        Permission::firstOrCreate([
            'name' => 'branches.view-all',
            'guard_name' => 'web',
        ]);

        $adminRole = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);

        $adminRole->syncPermissions([
            'customers.manage',
            'branches.view-all',
        ]);

        $admin = User::factory()->create(['business_id' => $this->business->id]);
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Customer',
        ]);

        $response = $this->actingAs($admin)
            ->getJson("/api/v1/customers?branch_id={$otherBranch->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertTrue(
            collect($response->json('data'))
                ->pluck('name')
                ->contains('Other Branch Customer')
        );
    }

    public function test_user_with_no_assigned_branch_gets_clear_error(): void
    {
        Permission::firstOrCreate([
            'name' => 'customers.manage',
            'guard_name' => 'web',
        ]);

        Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ])->syncPermissions(['customers.manage']);

        $user = User::factory()->create(['business_id' => $this->business->id]);
        $user->assignRole('cashier');

        $response = $this->actingAs($user)
            ->getJson('/api/v1/customers');

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_invalid_branch_id_fails_validation(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/customers?branch_id=999999');

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_customer_search_matches_name_phone_or_email(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
            'phone' => '012345678',
            'email' => 'dara@example.com',
        ]);

        Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Sokha Tea',
            'phone' => '098765432',
            'email' => 'sokha@example.com',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/customers?search=012345678');

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $names = collect($response->json('data'))
            ->pluck('name');

        $this->assertTrue($names->contains('Dara Coffee'));
        $this->assertFalse($names->contains('Sokha Tea'));
    }

    public function test_store_creates_customer_in_current_branch(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/customers', [
                'name' => 'Dara Coffee',
                'phone' => '012345678',
                'email' => 'dara@example.com',
                'notes' => 'Regular customer',
            ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Dara Coffee')
            ->assertJsonPath('data.phone', '012345678')
            ->assertJsonPath('data.branch_id', $branch->id);

        $this->assertDatabaseHas('customers', [
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
            'phone' => '012345678',
            'email' => 'dara@example.com',
        ]);
    }

    public function test_store_with_unassigned_branch_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/customers', [
                'branch_id' => $otherBranch->id,
                'name' => 'Blocked Customer',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseMissing('customers', [
            'name' => 'Blocked Customer',
        ]);
    }

    public function test_update_customer_in_own_branch_works(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Old Name',
            'phone' => '012345678',
        ]);

        $response = $this->actingAs($user)
            ->patchJson("/api/v1/customers/{$customer->id}", [
                'name' => 'New Name',
                'phone' => '098765432',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'New Name')
            ->assertJsonPath('data.phone', '098765432');

        $this->assertDatabaseHas('customers', [
            'id' => $customer->id,
            'name' => 'New Name',
            'phone' => '098765432',
        ]);
    }

    public function test_update_customer_in_another_branch_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Protected Customer',
        ]);

        $response = $this->actingAs($user)
            ->patchJson("/api/v1/customers/{$customer->id}", [
                'name' => 'Changed Name',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('customers', [
            'id' => $customer->id,
            'name' => 'Protected Customer',
        ]);
    }

    public function test_global_customer_cannot_be_updated(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => null,
            'name' => 'Global Customer',
        ]);

        $response = $this->actingAs($user)
            ->patchJson("/api/v1/customers/{$customer->id}", [
                'name' => 'Changed Global Customer',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('customers', [
            'id' => $customer->id,
            'name' => 'Global Customer',
            'branch_id' => null,
        ]);
    }

    public function test_show_customer_in_own_branch_works(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
            'phone' => '012345678',
        ]);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $customer->id)
            ->assertJsonPath('data.name', 'Dara Coffee');
    }

    public function test_show_customer_in_another_branch_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Customer',
        ]);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_destroy_customer_soft_deletes_own_branch_customer(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Customer To Delete',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson("/api/v1/customers/{$customer->id}");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('customers', [
            'id' => $customer->id,
        ]);
    }

    public function test_destroy_customer_in_another_branch_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Protected Customer',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson("/api/v1/customers/{$customer->id}");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('customers', [
            'id' => $customer->id,
            'name' => 'Protected Customer',
            'deleted_at' => null,
        ]);
    }

    public function test_global_customer_cannot_be_deleted(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => null,
            'name' => 'Global Customer',
        ]);

        $response = $this->actingAs($user)
            ->deleteJson("/api/v1/customers/{$customer->id}");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertDatabaseHas('customers', [
            'id' => $customer->id,
            'name' => 'Global Customer',
            'deleted_at' => null,
        ]);
    }

    public function test_customer_orders_returns_completed_orders(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
        ]);

        $order = $this->createCustomerOrder(
            $branch,
            $user,
            $customer,
            'completed'
        );

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}/orders");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $ids = collect($response->json('data'))
            ->pluck('id');

        $this->assertTrue($ids->contains($order->id));
    }

    public function test_customer_orders_excludes_non_completed_orders(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
        ]);

        $completed = $this->createCustomerOrder(
            $branch,
            $user,
            $customer,
            'completed'
        );

        $this->createCustomerOrder(
            $branch,
            $user,
            $customer,
            'cancelled'
        );

        $this->createCustomerOrder(
            $branch,
            $user,
            $customer,
            'held'
        );

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}/orders");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $orders = collect($response->json('data'));

        $this->assertCount(1, $orders);
        $this->assertSame($completed->id, $orders->first()['id']);
    }

    public function test_customer_orders_are_limited_to_that_customer(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
        ]);

        $otherCustomer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Sokha Tea',
        ]);

        $customerOrder = $this->createCustomerOrder(
            $branch,
            $user,
            $customer
        );

        $this->createCustomerOrder(
            $branch,
            $user,
            $otherCustomer
        );

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}/orders");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $orders = collect($response->json('data'));

        $this->assertCount(1, $orders);
        $this->assertSame($customerOrder->id, $orders->first()['id']);
    }

    public function test_customer_orders_rejects_customer_from_another_branch(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $otherBranch = $this->createBranch('BKK1', 'PP-02');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Customer',
        ]);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}/orders");

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_customer_orders_support_pagination(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Dara Coffee',
        ]);

        for ($i = 0; $i < 3; $i++) {
            $this->createCustomerOrder(
                $branch,
                $user,
                $customer
            );
        }

        $response = $this->actingAs($user)
            ->getJson("/api/v1/customers/{$customer->id}/orders?per_page=2");

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('meta.per_page', 2)
            ->assertJsonPath('meta.total', 3)
            ->assertJsonPath('meta.last_page', 2);

        $this->assertCount(2, $response->json('data'));
    }

    public function test_manual_loyalty_adjustment_adds_points_and_creates_transaction(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        Permission::firstOrCreate([
            'name' => 'loyalty.manage',
            'guard_name' => 'web',
        ]);

        $user->givePermissionTo('loyalty.manage');

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Loyalty Customer',
            'phone' => '012345678',
        ]);

        $response = $this->actingAs($user)->postJson(
            "/api/v1/customers/{$customer->id}/loyalty/adjust",
            [
                'points' => 50,
                'description' => 'Welcome bonus',
                'branch_id' => $branch->id,
            ],
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $account = CustomerLoyaltyAccount::where('customer_id', $customer->id)
            ->firstOrFail();

        $this->assertSame(50, (int) $account->points_balance);
        $this->assertSame(0, (int) $account->lifetime_earned);
        $this->assertSame(0, (int) $account->lifetime_redeemed);

        $this->assertDatabaseHas('loyalty_transactions', [
            'customer_id' => $customer->id,
            'branch_id' => $branch->id,
            'type' => 'adjustment',
            'points' => 50,
            'balance_after' => 50,
            'description' => 'Welcome bonus',
        ]);

        $this->assertSame(1, LoyaltyTransaction::where('customer_id', $customer->id)->count());
    }


    public function test_manual_loyalty_adjustment_cannot_make_balance_negative(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeUserForBranch($branch);

        Permission::firstOrCreate([
            'name' => 'loyalty.manage',
            'guard_name' => 'web',
        ]);

        $user->givePermissionTo('loyalty.manage');

        $customer = Customer::forceCreate(['business_id' => $this->business->id,
            'branch_id' => $branch->id,
            'name' => 'Loyalty Customer',
            'phone' => '012345679',
        ]);

        $this->actingAs($user)->postJson(
            "/api/v1/customers/{$customer->id}/loyalty/adjust",
            [
                'points' => 50,
                'description' => 'Welcome bonus',
                'branch_id' => $branch->id,
            ],
        )->assertStatus(200);

        $response = $this->actingAs($user)->postJson(
            "/api/v1/customers/{$customer->id}/loyalty/adjust",
            [
                'points' => -100,
                'description' => 'Too many points removed',
                'branch_id' => $branch->id,
            ],
        );

        $response
            ->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Loyalty points balance cannot be negative.');

        $account = CustomerLoyaltyAccount::where('customer_id', $customer->id)
            ->firstOrFail();

        $this->assertSame(50, (int) $account->points_balance);
        $this->assertSame(1, LoyaltyTransaction::where('customer_id', $customer->id)->count());
    }

}
