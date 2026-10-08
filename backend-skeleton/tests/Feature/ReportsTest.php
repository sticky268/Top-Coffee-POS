<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Category;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ReportsTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

    private function seedReportsPermissions(): void
    {
        Permission::firstOrCreate([
            'name' => 'reports.view',
            'guard_name' => 'web',
        ]);

        Permission::firstOrCreate([
            'name' => 'branches.view-all',
            'guard_name' => 'web',
        ]);

        $manager = Role::firstOrCreate([
            'name' => 'manager',
            'guard_name' => 'web',
        ]);
        $manager->syncPermissions(['reports.view']);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);
        $admin->syncPermissions([
            'reports.view',
            'branches.view-all',
        ]);

        Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ]);
    }

    private function makeUserForBranch(
        Branch $branch,
        string $role = 'manager'
    ): User {
        Role::firstOrCreate([
            'name' => $role,
            'guard_name' => 'web',
        ]);

        $user = User::factory()->create(['business_id' => $branch->business_id]);
        $user->assignRole($role);
        $user->branches()->attach($branch->id, ['is_primary' => true]);

        return $user;
    }

    private function makeProduct(
        Category $category,
        string $name,
        float $price
    ): Product {
        return Product::create([
            'category_id' => $category->id,
            'name' => $name,
            'base_price' => $price,
        ]);
    }

    private function makeOrder(
        Branch $branch,
        User $user,
        array $overrides = []
    ): Order {
        $createdAt = $overrides['created_at'] ?? null;
        unset($overrides['created_at']);

        $order = Order::create(array_merge([
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branch->id,
            'user_id' => $user->id,
            'order_type' => 'takeaway',
            'status' => 'completed',
            'subtotal' => 10.00,
            'discount_total' => 0,
            'tax_total' => 0,
            'total' => 10.00,
            'sync_status' => 'synced',
        ], $overrides));

        if ($createdAt !== null) {
            $order->created_at = $createdAt;
            $order->saveQuietly();
        }

        return $order;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/reports')
            ->assertStatus(401);
    }

    public function test_user_without_reports_permission_cannot_view_reports(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeUserForBranch($branch, 'cashier');

        $this->actingAs($user)
            ->getJson('/api/v1/reports')
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_manager_can_view_report_summary_and_sales_overview(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeUserForBranch($branch);

        $this->makeOrder($branch, $user, [
            'total' => 12.50,
            'subtotal' => 12.50,
            'created_at' => '2026-09-23 10:00:00',
        ]);

        $this->makeOrder($branch, $user, [
            'total' => 7.50,
            'subtotal' => 7.50,
            'created_at' => '2026-09-23 12:00:00',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/reports?date_from=2026-09-23&date_to=2026-09-23');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.summary.total_sales', 20)
            ->assertJsonPath('data.summary.total_orders', 2)
            ->assertJsonPath('data.summary.average_order_value', 10)
            ->assertJsonPath('data.sales_overview.0.date', '2026-09-23')
            ->assertJsonPath('data.sales_overview.0.total', 20)
            ->assertJsonCount(24, 'data.hourly_sales')
            ->assertJsonPath('data.hourly_sales.10.hour', '10:00')
            ->assertJsonPath('data.hourly_sales.10.total', 12.50)
            ->assertJsonPath('data.hourly_sales.12.hour', '12:00')
            ->assertJsonPath('data.hourly_sales.12.total', 7.50);
    }

    public function test_report_includes_payment_methods_order_types_and_top_products(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeUserForBranch($branch);

        $category = Category::forceCreate(['business_id' => $this->business->id,
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $latte = $this->makeProduct($category, 'Latte', 3.50);
        $tea = $this->makeProduct($category, 'Green Tea', 2.50);

        $order = $this->makeOrder($branch, $user, [
            'order_type' => 'dine_in',
            'total' => 8.50,
            'subtotal' => 8.50,
            'created_at' => '2026-09-23 10:00:00',
        ]);

        OrderItem::create([
            'order_id' => $order->id,
            'product_id' => $latte->id,
            'quantity' => 2,
            'unit_price' => 3.50,
        ]);

        OrderItem::create([
            'order_id' => $order->id,
            'product_id' => $tea->id,
            'quantity' => 1,
            'unit_price' => 1.50,
        ]);

        Payment::create([
            'order_id' => $order->id,
            'method' => 'cash',
            'amount' => 8.50,
            'status' => 'completed',
            'processed_by' => $user->id,
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/reports?date_from=2026-09-23&date_to=2026-09-23');

        $response->assertStatus(200);

        $this->assertSame(
            'dine_in',
            $response->json('data.order_types.0.type')
        );
        $this->assertSame(
            1,
            $response->json('data.order_types.0.count')
        );
        $this->assertEquals(
            8.50,
            $response->json('data.order_types.0.total')
        );

        $this->assertSame(
            'cash',
            $response->json('data.payment_methods.0.method')
        );
        $this->assertEquals(
            8.50,
            $response->json('data.payment_methods.0.total')
        );
        $this->assertSame(
            1,
            $response->json('data.payment_methods.0.count')
        );

        $topProducts = $response->json('data.top_products');

        $this->assertSame('Latte', $topProducts[0]['product_name']);
        $this->assertSame(2, $topProducts[0]['quantity_sold']);
        $this->assertEquals(7.00, $topProducts[0]['sales_total']);

        $this->assertSame('Green Tea', $topProducts[1]['product_name']);
        $this->assertSame(1, $topProducts[1]['quantity_sold']);
        $this->assertEquals(1.50, $topProducts[1]['sales_total']);
    }

    public function test_report_filters_by_date_range(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeUserForBranch($branch);

        $this->makeOrder($branch, $user, [
            'total' => 10.00,
            'subtotal' => 10.00,
            'created_at' => '2026-09-22 10:00:00',
        ]);

        $this->makeOrder($branch, $user, [
            'total' => 25.00,
            'subtotal' => 25.00,
            'created_at' => '2026-09-23 10:00:00',
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/reports?date_from=2026-09-23&date_to=2026-09-23');

        $response->assertStatus(200)
            ->assertJsonPath('data.summary.total_sales', 25)
            ->assertJsonPath('data.summary.total_orders', 1);
    }

    public function test_manager_cannot_access_report_for_another_branch(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $otherBranch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $user = $this->makeUserForBranch($branch);

        $response = $this->actingAs($user)
            ->getJson("/api/v1/reports?branch_id={$otherBranch->id}");

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_payment_breakdown_counts_only_completed_collections(): void
    {
        $this->seedReportsPermissions();
        $branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $user = $this->makeUserForBranch($branch);
        $order = $this->makeOrder($branch, $user);
        foreach (['completed' => 10, 'pending' => 100, 'failed' => 1000, 'refunded' => 10000] as $status => $amount) {
            Payment::create(['order_id' => $order->id, 'method' => 'cash', 'amount' => $amount,
                'status' => $status, 'processed_by' => $user->id]);
        }
        $this->actingAs($user)->getJson('/api/v1/reports')
            ->assertOk()->assertJsonPath('data.summary.total_sales', 10)
            ->assertJsonPath('data.payment_methods.0.total', 10)
            ->assertJsonPath('data.payment_methods.0.count', 1);
    }

    public function test_admin_report_and_dashboard_cannot_read_another_business(): void
    {
        $this->seedReportsPermissions();
        Permission::firstOrCreate(['name' => 'orders.view', 'guard_name' => 'web']);
        $own = Branch::factory()->create(['business_id' => $this->business->id]);
        $foreign = Branch::factory()->create(['business_id' => Business::factory()->create()->id]);
        $admin = $this->makeUserForBranch($own, 'admin');
        $admin->givePermissionTo('orders.view');
        $otherUser = $this->makeUserForBranch($foreign);
        $ownOrder = $this->makeOrder($own, $admin);
        $foreignOrder = $this->makeOrder($foreign, $otherUser, ['total' => 90, 'subtotal' => 90]);
        Payment::create(['order_id' => $ownOrder->id, 'method' => 'cash', 'amount' => 10,
            'status' => 'completed', 'processed_by' => $admin->id]);
        Payment::create(['order_id' => $foreignOrder->id, 'method' => 'card', 'amount' => 90,
            'status' => 'completed', 'processed_by' => $otherUser->id]);
        foreach ([[$ownOrder, 'Own product', 10], [$foreignOrder, 'Foreign product', 90]] as [$order, $name, $price]) {
            $category = Category::forceCreate(['business_id' => $order->branch->business_id, 'name' => 'Audit fixture', 'branch_id' => null]);
            $product = $this->makeProduct($category, $name, $price);
            OrderItem::create(['order_id' => $order->id, 'product_id' => $product->id,
                'product_name' => $name, 'quantity' => 1, 'unit_price' => $price, 'line_total' => $price]);
        }
        $unitId = \Illuminate\Support\Facades\DB::table('units')->insertGetId([
            'name' => 'Audit gram', 'abbreviation' => 'g', 'conversion_factor' => 1,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        foreach ([$own, $foreign] as $branch) {
            \App\Models\Ingredient::create(['branch_id' => $branch->id, 'unit_id' => $unitId,
                'name' => 'Low stock fixture', 'reorder_threshold' => 1, 'is_active' => true]);
        }
        $this->actingAs($admin)->getJson('/api/v1/reports')->assertOk()
            ->assertJsonPath('data.summary.total_sales', 10)
            ->assertJsonCount(1, 'data.payment_methods')
            ->assertJsonPath('data.top_products.0.product_name', 'Own product');
        $this->getJson('/api/v1/dashboard')->assertOk()
            ->assertJsonPath('data.stats.todays_sales', 10)
            ->assertJsonPath('data.stats.low_stock_item_count', 1)
            ->assertJsonCount(1, 'data.recent_orders');
        $this->getJson('/api/v1/reports?branch_id='.$foreign->id)->assertForbidden();
        $this->getJson('/api/v1/dashboard?branch_id='.$foreign->id)->assertForbidden();
    }

    public function test_dashboard_uses_branch_order_number_and_completed_split_payments(): void
    {
        $this->seedReportsPermissions();
        Permission::firstOrCreate(['name' => 'orders.view', 'guard_name' => 'web']);
        $branch = Branch::factory()->create(['business_id' => $this->business->id]);
        $user = $this->makeUserForBranch($branch, 'admin');
        $user->givePermissionTo('orders.view');
        $order = $this->makeOrder($branch, $user, ['order_number' => 42]);
        foreach ([['card', 100, 'failed'], ['cash', 4, 'completed'], ['qr', 6, 'completed']] as [$method, $amount, $status]) {
            Payment::create(['order_id' => $order->id, 'method' => $method, 'amount' => $amount,
                'status' => $status, 'processed_by' => $user->id]);
        }
        $this->actingAs($user)->getJson('/api/v1/dashboard')->assertOk()
            ->assertJsonPath('data.recent_orders.0.order_number', '42')
            ->assertJsonPath('data.recent_orders.0.payment_method', 'split');
    }

    public function test_business_isolation_does_not_hide_archived_branch_sales_from_admin(): void
    {
        $this->seedReportsPermissions();
        $branch = Branch::factory()->create(['business_id'=>$this->business->id]);
        $admin = $this->makeUserForBranch($branch,'admin');
        $this->makeOrder($branch,$admin);
        $branch->delete();
        $this->actingAs($admin)->getJson('/api/v1/reports')->assertOk()->assertJsonPath('data.summary.total_sales',10);
        $this->getJson('/api/v1/reports?branch_id='.$branch->id)->assertOk()->assertJsonPath('data.summary.total_sales',10);
    }

    public function test_admin_can_view_another_branch_report(): void
    {
        $this->seedReportsPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $otherBranch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'BKK1',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeUserForBranch($branch, 'admin');

        $this->makeOrder($otherBranch, $admin, [
            'total' => 30.00,
            'subtotal' => 30.00,
            'created_at' => '2026-09-23 10:00:00',
        ]);

        $response = $this->actingAs($admin)
            ->getJson("/api/v1/reports?branch_id={$otherBranch->id}&date_from=2026-09-23&date_to=2026-09-23");

        $response->assertStatus(200)
            ->assertJsonPath('data.summary.total_sales', 30)
            ->assertJsonPath('data.summary.total_orders', 1);
    }
}
