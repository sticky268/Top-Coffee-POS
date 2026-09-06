<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class OrderListingTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach (['orders.view', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }

        $cashier = Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
        $cashier->syncPermissions(['orders.view']);

        $admin = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $admin->syncPermissions(['orders.view', 'branches.view-all']);

        // Deliberately no 'orders.view' synced here — used by the
        // permission-rejection test below.
        Role::firstOrCreate(['name' => 'kitchen_staff', 'guard_name' => 'web']);
    }

    private function makeCashier(Branch $branch): User
    {
        $this->seedPermissions();
        $user = User::factory()->create();
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    private function createOrder(Branch $branch, User $cashier, array $overrides = []): Order
    {
        $category = Category::firstOrCreate(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.00]);

        $order = Order::create(array_merge([
            'uuid' => (string) Str::uuid(),
            'branch_id' => $branch->id,
            'user_id' => $cashier->id,
            'order_type' => 'takeaway',
            'status' => 'completed',
            'subtotal' => 3.00,
            'discount_total' => 0,
            'tax_total' => 0,
            'total' => 3.00,
            'completed_at' => now(),
        ], $overrides));

        OrderItem::create([
            'order_id' => $order->id,
            'product_id' => $product->id,
            'product_variant_id' => null,
            'quantity' => 1,
            'unit_price' => 3.00,
        ]);

        Payment::create([
            'order_id' => $order->id,
            'method' => 'cash',
            'amount' => 3.00,
            'tendered' => 5.00,
            'change_due' => 2.00,
            'status' => 'completed',
            'processed_by' => $cashier->id,
        ]);

        return $order;
    }

    // --- index() -------------------------------------------------------

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/orders')->assertStatus(401);
    }

    public function test_user_without_orders_view_permission_is_rejected(): void
    {
        $this->seedPermissions();
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $kitchenUser = User::factory()->create();
        $kitchenUser->assignRole('kitchen_staff');
        $kitchenUser->branches()->attach($branch->id, ['is_primary' => true]);

        $response = $this->actingAs($kitchenUser)->getJson('/api/v1/orders');

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_authenticated_user_can_list_their_branchs_orders(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);
        $this->createOrder($branch, $cashier);
        $this->createOrder($branch, $cashier);

        $response = $this->actingAs($cashier)->getJson('/api/v1/orders');

        $response->assertStatus(200)->assertJsonPath('success', true);
        $this->assertCount(2, $response->json('data'));
        $this->assertEquals(2, $response->json('meta.total'));
    }

    public function test_branch_scoping_hides_other_branches_orders_from_the_list(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $cashier = $this->makeCashier($branch);

        $ownOrder = $this->createOrder($branch, $cashier);
        $otherOrder = $this->createOrder($otherBranch, $cashier);

        $response = $this->actingAs($cashier)->getJson('/api/v1/orders');

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertTrue($ids->contains($ownOrder->id));
        $this->assertFalse($ids->contains($otherOrder->id));
    }

    public function test_admin_with_view_all_sees_orders_from_every_branch(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $this->seedPermissions();

        $cashier = User::factory()->create();
        $cashier->assignRole('cashier');
        $cashier->branches()->attach($branch->id, ['is_primary' => true]);

        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        $orderA = $this->createOrder($branch, $cashier);
        $orderB = $this->createOrder($otherBranch, $cashier);

        $response = $this->actingAs($admin)->getJson('/api/v1/orders');

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertTrue($ids->contains($orderA->id));
        $this->assertTrue($ids->contains($orderB->id));
    }

    public function test_pagination_returns_correct_meta_and_limits_page_size(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);

        for ($i = 0; $i < 5; $i++) {
            $this->createOrder($branch, $cashier);
        }

        $response = $this->actingAs($cashier)->getJson('/api/v1/orders?per_page=2');

        $response->assertStatus(200);
        $this->assertCount(2, $response->json('data'));
        $this->assertEquals(1, $response->json('meta.current_page'));
        $this->assertEquals(3, $response->json('meta.last_page')); // 5 orders / 2 per page
        $this->assertEquals(2, $response->json('meta.per_page'));
        $this->assertEquals(5, $response->json('meta.total'));

        $secondPage = $this->actingAs($cashier)->getJson('/api/v1/orders?per_page=2&page=2');
        $this->assertCount(2, $secondPage->json('data'));
        $this->assertEquals(2, $secondPage->json('meta.current_page'));
    }

    public function test_filters_by_order_number_status_and_payment_method(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);

        $target = $this->createOrder($branch, $cashier);
        $this->createOrder($branch, $cashier, ['status' => 'cancelled']);

        $byId = $this->actingAs($cashier)->getJson("/api/v1/orders?order_number={$target->id}");
        $this->assertCount(1, $byId->json('data'));
        $this->assertEquals($target->id, $byId->json('data.0.id'));

        $byUuid = $this->actingAs($cashier)->getJson('/api/v1/orders?order_number='.substr($target->uuid, 0, 8));
        $this->assertCount(1, $byUuid->json('data'));

        $byStatus = $this->actingAs($cashier)->getJson('/api/v1/orders?status=cancelled');
        $this->assertCount(1, $byStatus->json('data'));
        $this->assertEquals('cancelled', $byStatus->json('data.0.status'));

        $byPayment = $this->actingAs($cashier)->getJson('/api/v1/orders?payment_method=cash');
        $this->assertCount(2, $byPayment->json('data'));

        $byMissingPayment = $this->actingAs($cashier)->getJson('/api/v1/orders?payment_method=qr');
        $this->assertCount(0, $byMissingPayment->json('data'));
    }

    public function test_date_range_filter_excludes_orders_outside_the_range(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);

        $order = $this->createOrder($branch, $cashier);
        $order->created_at = now()->subDays(10);
        $order->save();

        $response = $this->actingAs($cashier)->getJson(
            '/api/v1/orders?date_from='.now()->subDay()->toDateString()
        );

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertFalse($ids->contains($order->id));
    }

    // --- show() ----------------------------------------------------------

    public function test_order_detail_returns_items_branch_cashier_and_payment(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);
        $order = $this->createOrder($branch, $cashier);

        $response = $this->actingAs($cashier)->getJson("/api/v1/orders/{$order->id}");

        $response->assertStatus(200)->assertJsonPath('success', true);
        $response->assertJsonPath('data.id', $order->id);
        $response->assertJsonCount(1, 'data.items');
        $response->assertJsonPath('data.items.0.product_name', 'Latte');
        $response->assertJsonPath('data.items.0.line_total', 3);
        $response->assertJsonPath('data.payment.method', 'cash');
        $response->assertJsonPath('data.payment.change_due', 2);
        $response->assertJsonPath('data.branch.name', 'Riverside');
        $response->assertJsonPath('data.cashier.name', $cashier->name);
    }

    public function test_an_order_from_another_branch_cannot_be_viewed(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $cashier = $this->makeCashier($branch);
        $otherOrder = $this->createOrder($otherBranch, $cashier);

        $response = $this->actingAs($cashier)->getJson("/api/v1/orders/{$otherOrder->id}");

        $response->assertStatus(404)->assertJsonPath('success', false);
    }

    public function test_a_nonexistent_order_returns_404(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);

        $response = $this->actingAs($cashier)->getJson('/api/v1/orders/999999');

        $response->assertStatus(404);
    }

    public function test_show_also_requires_orders_view_permission(): void
    {
        $this->seedPermissions();
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $cashier = $this->makeCashier($branch);
        $order = $this->createOrder($branch, $cashier);

        $kitchenUser = User::factory()->create();
        $kitchenUser->assignRole('kitchen_staff');
        $kitchenUser->branches()->attach($branch->id, ['is_primary' => true]);

        $response = $this->actingAs($kitchenUser)->getJson("/api/v1/orders/{$order->id}");

        $response->assertStatus(403)->assertJsonPath('success', false);
    }
}
