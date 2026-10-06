<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Branch;
use App\Models\Business;
use App\Models\Category;
use App\Models\Customer;
use App\Models\Ingredient;
use App\Models\LoyaltySetting;
use App\Models\LoyaltyTransaction;
use App\Models\Order;
use App\Models\Payment;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\RecipeItem;
use App\Models\RestaurantTable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class OrderTest extends TestCase
{
    use RefreshDatabase;

    private Business $business;

    protected function setUp(): void
    {
        parent::setUp();

        $this->business = Business::factory()->create();
    }

    private function seedPermissions(): void
    {
        foreach (['orders.create', 'orders.edit', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }

        $cashier = Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
        $cashier->syncPermissions(['orders.create']);

        $admin = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $admin->syncPermissions(['orders.create', 'orders.edit', 'branches.view-all']);

        $manager = Role::firstOrCreate(['name' => 'manager', 'guard_name' => 'web']);
        $manager->syncPermissions(['orders.edit']);
    }

    private function makeCashier(Branch $branch): User
    {
        $this->seedPermissions();
        $user = User::factory()->create();
        $user->assignRole('cashier');
        $user->branches()->attach($branch->id, ['is_primary' => true]);

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
        $ingredient = Ingredient::create([
            'branch_id' => $branch->id,
            'unit_id' => $unitId,
            'name' => $name,
            'reorder_threshold' => 10,
            'is_active' => true,
        ]);

        $createdBy = User::query()
            ->whereHas('branches', fn ($query) => $query->where('branches.id', $branch->id))
            ->value('id');

        if ($createdBy === null) {
            throw new \RuntimeException('No test user is assigned to the ingredient branch.');
        }

        app(\App\Services\StockMovementService::class)->record(
            $ingredient,
            'purchase',
            $stock,
            $createdBy,
            'Initial test stock',
        );

        return $ingredient->fresh();
    }
    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->postJson('/api/v1/orders', [])->assertStatus(401);
    }

    public function test_user_without_orders_create_permission_is_rejected(): void
    {
        $this->seedPermissions();
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $manager = User::factory()->create();
        $manager->assignRole('manager'); // no orders.create permission
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        $response = $this->actingAs($manager)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [],
            'payment' => ['method' => 'cash'],
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_creates_an_order_with_correct_server_computed_total(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $latte = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.50]);
        $latte->branches()->attach($branch->id, ['is_available' => true, 'price_override' => 3.00]);
        $large = ProductVariant::create(['product_id' => $latte->id, 'name' => 'Large', 'price_delta' => 0.75]);

        $americano = Product::create(['category_id' => $category->id, 'name' => 'Americano', 'base_price' => 2.50]);
        $americano->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                ['product_id' => $latte->id, 'product_variant_id' => $large->id, 'quantity' => 2], // 3.75 x 2 = 7.50
                ['product_id' => $americano->id, 'product_variant_id' => null, 'quantity' => 1],    // 2.50 x 1 = 2.50
            ],
            'payment' => ['method' => 'cash', 'tendered' => 15.00],
        ]);

        $response->assertStatus(201)->assertJsonPath('success', true);
        $this->assertSame(10.0, (float) $response->json('data.subtotal'));
        $this->assertSame(10.0, (float) $response->json('data.total'));
        $response->assertJsonPath('data.payment.method', 'cash');
        $this->assertSame(15.0, (float) $response->json('data.payment.tendered'));
        $this->assertSame(5.0, (float) $response->json('data.payment.change_due'));

        $this->assertDatabaseCount('orders', 1);
        $this->assertDatabaseCount('order_items', 2);
        $this->assertDatabaseCount('payments', 1);

        $order = Order::first();
        $this->assertEquals('completed', $order->status);
        $this->assertEquals($branch->id, $order->branch_id);
        $this->assertEquals($user->id, $order->user_id);

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'order.created',
            'auditable_type' => $order->getMorphClass(),
            'auditable_id' => $order->id,
        ]);

        $auditLog = AuditLog::query()
            ->where('action', 'order.created')
            ->where('auditable_id', $order->id)
            ->firstOrFail();

        $this->assertSame($branch->id, $auditLog->new_values['branch_id']);
        $this->assertSame($user->id, $auditLog->user_id);
        $this->assertSame('completed', $auditLog->new_values['status']);
        $this->assertSame(10.0, (float) $auditLog->new_values['total']);
    }

    public function test_creates_an_order_for_a_customer(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 5.00]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        $customer = Customer::create([
            'branch_id' => $branch->id,
            'name' => 'Test Customer',
            'phone' => '012345678',
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'customer_id' => $customer->id,
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'cash', 'tendered' => 10.00],
        ]);

        $response->assertStatus(201);
        $response->assertJsonPath('data.customer_id', $customer->id);

        $order = Order::first();
        $this->assertEquals($customer->id, $order->customer_id);
    }

    public function test_rejects_a_customer_from_another_branch(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'Downtown', 'code' => 'PP-02']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 5.00]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        $customer = Customer::create([
            'branch_id' => $otherBranch->id,
            'name' => 'Other Branch Customer',
            'phone' => '012345679',
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'customer_id' => $customer->id,
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'cash', 'tendered' => 10.00],
        ]);

        $response->assertStatus(422);
        $response->assertJsonPath('message', 'Customer is not available at this branch.');
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_discount_total_reduces_the_final_total(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 5.00]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'discount_total' => 1.00,
            'payment' => ['method' => 'card'],
        ]);

        $response->assertStatus(201);
        $this->assertSame(5.0, (float) $response->json('data.subtotal'));
        $this->assertSame(1.0, (float) $response->json('data.discount_total'));
        $this->assertSame(4.0, (float) $response->json('data.total'));
    }

    public function test_card_payment_has_no_tendered_or_change_due(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.00]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'qr'],
        ]);

        $response->assertStatus(201);
        $response->assertJsonPath('data.payment.tendered', null);
        $response->assertJsonPath('data.payment.change_due', null);
    }

    public function test_split_payment_creates_multiple_payment_records(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 10.00,
        ]);

        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                ['product_id' => $product->id, 'quantity' => 1],
            ],
            'payment' => [
                'method' => 'split',
                'payments' => [
                    [
                        'method' => 'cash',
                        'amount' => 4.00,
                        'tendered' => 5.00,
                    ],
                    [
                        'method' => 'qr',
                        'amount' => 6.00,
                    ],
                ],
            ],
        ]);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.payment.method', 'split');

        $this->assertDatabaseCount('orders', 1);
        $this->assertDatabaseCount('payments', 2);

        $order = Order::first();

        $this->assertEquals('completed', $order->status);

        $this->assertDatabaseHas('payments', [
            'order_id' => $order->id,
            'method' => 'cash',
            'amount' => 4.00,
            'tendered' => 5.00,
            'change_due' => 1.00,
            'status' => 'completed',
        ]);

        $this->assertDatabaseHas('payments', [
            'order_id' => $order->id,
            'method' => 'qr',
            'amount' => 6.00,
            'tendered' => null,
            'change_due' => null,
            'status' => 'completed',
        ]);
    }

    public function test_split_payment_must_equal_order_total(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 10.00,
        ]);

        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                ['product_id' => $product->id, 'quantity' => 1],
            ],
            'payment' => [
                'method' => 'split',
                'payments' => [
                    [
                        'method' => 'cash',
                        'amount' => 4.00,
                        'tendered' => 5.00,
                    ],
                    [
                        'method' => 'qr',
                        'amount' => 5.00,
                    ],
                ],
            ],
        ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('order_items', 0);
        $this->assertDatabaseCount('payments', 0);
    }
    public function test_an_unavailable_product_rejects_the_whole_order_and_creates_nothing(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $validProduct = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.00]);
        $validProduct->branches()->attach($branch->id, ['is_available' => true]);

        // Only available at the OTHER branch +���+����+����+�-�+���+�-�+�-�+����-�+�-�+����+�-�+���+�-�+�-�+���+�+�-�+����+�-� not sellable at $branch.
        $invalidProduct = Product::create(['category_id' => $category->id, 'name' => 'Cold Brew', 'base_price' => 4.00]);
        $invalidProduct->branches()->attach($otherBranch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                ['product_id' => $validProduct->id, 'quantity' => 1],
                ['product_id' => $invalidProduct->id, 'quantity' => 1],
            ],
            'payment' => ['method' => 'cash', 'tendered' => 10],
        ]);

        $response->assertStatus(422)->assertJsonPath('success', false);

        // Critical: the transaction must have rolled back completely +���+����+����+�-�+���+�-�+�-�+����-�+�-�+����+�-�+���+�-�+�-�+���+�+�-�+����+�-�
        // not even the valid line should exist.
        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('order_items', 0);
        $this->assertDatabaseCount('payments', 0);
    }

    public function test_explicit_branch_id_for_an_unassigned_branch_is_rejected(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['business_id' => $this->business->id, 'name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeCashier($branch);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'branch_id' => $otherBranch->id,
            'order_type' => 'takeaway',
            'items' => [],
            'payment' => ['method' => 'cash'],
        ]);

        $response->assertStatus(403)->assertJsonPath('success', false);
    }

    public function test_validation_rejects_an_empty_items_array(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [],
            'payment' => ['method' => 'cash'],
        ]);

        $response->assertStatus(422)->assertJsonPath('success', false);
    }
    public function test_dine_in_order_requires_a_table(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id, 'name' => 'Riverside', 'code' => 'PP-01']);
        $user = $this->makeCashier($branch);

        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);
        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.00,
        ]);
        $product->branches()->attach($branch->id, ['is_available' => true]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'dine_in',
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'cash', 'tendered' => 5],
        ]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonValidationErrors(['table_id']);
    }
    public function test_held_dine_in_order_does_not_deduct_inventory(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            1000,
        );

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
        ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held');

        $this->assertSame(100.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(1000.0, (float) $milk->fresh()->current_stock);

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $coffee->id,
            'type' => 'sale_deduction',
        ]);

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $milk->id,
            'type' => 'sale_deduction',
        ]);

        $this->assertSame(
            'occupied',
            $table->fresh()->status,
        );

        $orderId = $response->json('data.id');

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'order.held',
            'auditable_type' => Order::class,
            'auditable_id' => $orderId,
        ]);

        $auditLog = AuditLog::query()
            ->where('action', 'order.held')
            ->where('auditable_id', $orderId)
            ->firstOrFail();

        $this->assertSame('held', $auditLog->new_values['status']);
        $this->assertSame($branch->id, $auditLog->new_values['branch_id']);
    }
    public function test_updating_held_order_records_audit_log(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $latte = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 5.00,
        ]);

        $americano = Product::create([
            'category_id' => $category->id,
            'name' => 'Americano',
            'base_price' => 3.00,
        ]);

        $latte->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $americano->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $holdResponse = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [
                [
                    'product_id' => $latte->id,
                    'quantity' => 1,
                ],
            ],
        ]);

        $holdResponse
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held')
            ->assertJsonPath('data.total', 5);

        $orderId = $holdResponse->json('data.id');

        $updateResponse = $this->actingAs($user)->patchJson(
            "/api/v1/orders/{$orderId}/hold",
            [
                'items' => [
                    [
                        'product_id' => $americano->id,
                        'quantity' => 2,
                    ],
                ],
            ],
        );

        $updateResponse
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held')
            ->assertJsonPath('data.total', 6);

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'order.updated',
            'auditable_type' => Order::class,
            'auditable_id' => $orderId,
        ]);

        $auditLog = AuditLog::query()
            ->where('action', 'order.updated')
            ->where('auditable_id', $orderId)
            ->firstOrFail();

        $this->assertSame(5.0, (float) $auditLog->old_values['total']);
        $this->assertSame(6.0, (float) $auditLog->new_values['total']);
        $this->assertSame('held', $auditLog->new_values['status']);
        $this->assertSame($branch->id, $auditLog->new_values['branch_id']);
        $this->assertSame($table->id, $auditLog->new_values['table_id']);
    }
    public function test_paid_held_dine_in_order_deducts_inventory(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            1000,
        );

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $holdResponse = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
        ]);

        $holdResponse
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held');

        $orderId = $holdResponse->json('data.id');

        $this->assertSame(100.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(1000.0, (float) $milk->fresh()->current_stock);

        $paymentResponse = $this->actingAs($user)->postJson(
            "/api/v1/orders/{$orderId}/pay",
            [
                'payment' => [
                    'method' => 'cash',
                    'tendered' => 5,
                ],
            ],
        );

        $paymentResponse
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.payment.status', 'completed');

        $this->assertSame(82.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(750.0, (float) $milk->fresh()->current_stock);
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'order.paid',
            'auditable_type' => Order::class,
            'auditable_id' => $orderId,
        ]);

        $auditLog = AuditLog::query()
            ->where('action', 'order.paid')
            ->where('auditable_id', $orderId)
            ->firstOrFail();

        $this->assertSame('held', $auditLog->old_values['status']);
        $this->assertSame('completed', $auditLog->new_values['status']);
        $this->assertSame($branch->id, $auditLog->new_values['branch_id']);
        $this->assertSame($table->id, $auditLog->new_values['table_id']);
        $this->assertSame(3.5, (float) $auditLog->new_values['total']);
        $this->assertSame('cash', $auditLog->new_values['payments'][0]['method']);
        $this->assertSame(3.5, (float) $auditLog->new_values['payments'][0]['amount']);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $coffee->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -18,
            'reason' => "Sale deduction for Order #{$orderId}",
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $milk->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -250,
            'reason' => "Sale deduction for Order #{$orderId}",
        ]);

        $this->assertSame(
            'available',
            $table->fresh()->status,
        );
    }
    public function test_held_dine_in_order_supports_split_payment(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 10.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $holdResponse = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
        ]);

        $holdResponse
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held');

        $orderId = $holdResponse->json('data.id');

        $paymentResponse = $this->actingAs($user)->postJson(
            "/api/v1/orders/{$orderId}/pay",
            [
                'payment' => [
                    'method' => 'split',
                    'payments' => [
                        [
                            'method' => 'cash',
                            'amount' => 4.00,
                            'tendered' => 5.00,
                        ],
                        [
                            'method' => 'qr',
                            'amount' => 6.00,
                        ],
                    ],
                ],
            ],
        );

        $paymentResponse
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.payment.method', 'split')
            ->assertJsonPath('data.payment.amount', 10)
            ->assertJsonPath('data.payment.tendered', null)
            ->assertJsonPath('data.payment.change_due', null)
            ->assertJsonCount(2, 'data.payments');

        $payments = $paymentResponse->json('data.payments');

        $this->assertSame('cash', $payments[0]['method']);
        $this->assertSame(4.0, (float) $payments[0]['amount']);
        $this->assertSame(5.0, (float) $payments[0]['tendered']);
        $this->assertSame(1.0, (float) $payments[0]['change_due']);

        $this->assertSame('qr', $payments[1]['method']);
        $this->assertSame(6.0, (float) $payments[1]['amount']);
        $this->assertNull($payments[1]['tendered']);
        $this->assertNull($payments[1]['change_due']);

        $this->assertDatabaseCount('payments', 2);

        $this->assertDatabaseHas('payments', [
            'order_id' => $orderId,
            'method' => 'cash',
            'amount' => 4.00,
            'tendered' => 5.00,
            'change_due' => 1.00,
            'status' => 'completed',
        ]);

        $this->assertDatabaseHas('payments', [
            'order_id' => $orderId,
            'method' => 'qr',
            'amount' => 6.00,
            'tendered' => null,
            'change_due' => null,
            'status' => 'completed',
        ]);

        $this->assertSame(
            'available',
            $table->fresh()->status,
        );
    }
    public function test_paid_held_dine_in_order_rolls_back_when_inventory_is_insufficient(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            100,
        );

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $holdResponse = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
        ]);

        $holdResponse
            ->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', 'held');

        $orderId = $holdResponse->json('data.id');

        $paymentResponse = $this->actingAs($user)->postJson(
            "/api/v1/orders/{$orderId}/pay",
            [
                'payment' => [
                    'method' => 'cash',
                    'tendered' => 5,
                ],
            ],
        );

        $paymentResponse
            ->assertStatus(500)
            ->assertJsonPath('success', false)
            ->assertJsonPath(
                'message',
                'Could not complete the payment. Please try again.'
            );

        $this->assertSame(100.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(100.0, (float) $milk->fresh()->current_stock);

        $this->assertSame(
            'held',
            Order::findOrFail($orderId)->status,
        );

        $this->assertSame(
            'occupied',
            $table->fresh()->status,
        );

        $this->assertDatabaseMissing('payments', [
            'order_id' => $orderId,
        ]);

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $coffee->id,
            'type' => 'sale_deduction',
        ]);

        $this->assertDatabaseMissing('stock_movements', [
            'ingredient_id' => $milk->id,
            'type' => 'sale_deduction',
        ]);
    }
    public function test_completed_sale_deducts_inventory_by_order_quantity(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            1000,
        );

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 2,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 10,
            ],
        ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true);

        $orderId = $response->json('data.id');

        $this->assertSame(64.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(500.0, (float) $milk->fresh()->current_stock);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $coffee->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -36,
            'reason' => 'Sale deduction for Order #' . $orderId,
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $milk->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -500,
            'reason' => 'Sale deduction for Order #' . $orderId,
        ]);
    }
    public function test_completed_sale_deducts_inventory_from_product_recipe(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 3.50,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            1000,
        );

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 18,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'modifier_id' => null,
            'ingredient_id' => $milk->id,
            'quantity_used' => 250,
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 5,
            ],
        ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('success', true);

        $orderId = $response->json('data.id');

        $this->assertSame(82.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(750.0, (float) $milk->fresh()->current_stock);
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'order.paid',
            'auditable_type' => Order::class,
            'auditable_id' => $orderId,
        ]);

        $auditLog = AuditLog::query()
            ->where('action', 'order.paid')
            ->where('auditable_id', $orderId)
            ->firstOrFail();

        $this->assertSame('held', $auditLog->old_values['status']);
        $this->assertSame('completed', $auditLog->new_values['status']);
        $this->assertSame($branch->id, $auditLog->new_values['branch_id']);
        $this->assertNull($auditLog->new_values['table_id']);
        $this->assertSame(3.5, (float) $auditLog->new_values['total']);
        $this->assertSame('cash', $auditLog->new_values['payments'][0]['method']);
        $this->assertSame(3.5, (float) $auditLog->new_values['payments'][0]['amount']);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $coffee->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -18,
            'reason' => 'Sale deduction for Order #' . $orderId,
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $milk->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -250,
            'reason' => 'Sale deduction for Order #' . $orderId,
        ]);
    }

    public function test_user_without_orders_edit_permission_is_rejected(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($cashier)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $product->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_manager_with_orders_edit_permission_can_edit_order(): void
    {
        $this->seedPermissions();

        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        $unitId = $this->createUnit();

        $oldIngredient = $this->createIngredient(
            $branch,
            $unitId,
            'Old Ingredient',
            100,
        );

        $newIngredient = $this->createIngredient(
            $branch,
            $unitId,
            'New Ingredient',
            100,
        );

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $oldProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Old Latte',
            'base_price' => 3.00,
        ]);

        $newProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'New Latte',
            'base_price' => 3.00,
        ]);

        $oldProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $newProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $oldProduct->id,
            'ingredient_id' => $oldIngredient->id,
            'quantity_used' => 10,
        ]);

        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $newProduct->id,
            'ingredient_id' => $newIngredient->id,
            'quantity_used' => 20,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $oldProduct->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');
        $orderUuid = $createResponse->json('data.uuid');

        $this->assertSame(90.0, (float) $oldIngredient->fresh()->current_stock);
        $this->assertSame(100.0, (float) $newIngredient->fresh()->current_stock);

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $newProduct->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('data.id', $orderId)
            ->assertJsonPath('data.uuid', $orderUuid)
            ->assertJsonPath('data.total', 3);

        $order = Order::withoutGlobalScopes()->findOrFail($orderId);

        $this->assertSame(3.0, (float) $order->total);
        $this->assertSame(
            $newProduct->id,
            $order->items()->firstOrFail()->product_id
        );

        $this->assertSame(
            100.0,
            (float) $oldIngredient->fresh()->current_stock
        );

        $this->assertSame(
            80.0,
            (float) $newIngredient->fresh()->current_stock
        );

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $oldIngredient->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -10,
            'reason' => "Sale deduction for Order #{$orderId}",
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $oldIngredient->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => 10,
            'reason' => "Sale reversal for Order #{$orderId}",
        ]);

        $this->assertDatabaseHas('stock_movements', [
            'ingredient_id' => $newIngredient->id,
            'branch_id' => $branch->id,
            'type' => 'sale_deduction',
            'quantity' => -20,
            'reason' => "Sale deduction for Order #{$orderId}",
        ]);
    }
    public function test_editing_order_after_recipe_change_reverses_original_inventory_usage(): void
    {
        $this->seedPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        Permission::firstOrCreate([
            'name' => 'inventory.manage',
            'guard_name' => 'web',
        ]);

        $manager->givePermissionTo('inventory.manage');

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $milk = $this->createIngredient(
            $branch,
            $unitId,
            'Milk',
            100,
        );

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $recipeItem = RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 10,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');

        $this->assertSame(90.0, (float) $coffee->fresh()->current_stock);
        $this->assertSame(100.0, (float) $milk->fresh()->current_stock);

        $recipeItem->update([
            'ingredient_id' => $milk->id,
            'quantity_used' => 20,
        ]);

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $product->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response->assertStatus(200);

        $this->assertSame(
            100.0,
            (float) $coffee->fresh()->current_stock,
        );

        $this->assertSame(
            80.0,
            (float) $milk->fresh()->current_stock,
        );

        $recipeItem->update([
            'ingredient_id' => $coffee->id,
            'quantity_used' => 5,
        ]);

        $secondResponse = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $product->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $secondResponse->assertStatus(200);

        $this->assertSame(
            95.0,
            (float) $coffee->fresh()->current_stock,
        );

        $this->assertSame(
            100.0,
            (float) $milk->fresh()->current_stock,
        );
    }

    public function test_editing_order_after_consumed_ingredient_is_soft_deleted_reverses_historical_usage(): void
    {
        $this->seedPermissions();

        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        Permission::firstOrCreate([
            'name' => 'inventory.manage',
            'guard_name' => 'web',
        ]);

        $manager->givePermissionTo('inventory.manage');

        $unitId = $this->createUnit();

        $coffee = $this->createIngredient(
            $branch,
            $unitId,
            'Coffee',
            100,
        );

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $recipeItem = RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $coffee->id,
            'quantity_used' => 10,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');

        $this->assertSame(
            90.0,
            (float) $coffee->fresh()->current_stock,
        );

        $recipeItem->delete();

        $deleteResponse = $this->actingAs($manager)->deleteJson(
            "/api/v1/ingredients/{$coffee->id}"
        );

        $deleteResponse
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $this->assertSoftDeleted('ingredients', [
            'id' => $coffee->id,
        ]);

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $product->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response->assertStatus(200);

        $this->assertSame(
            100.0,
            (float) Ingredient::withTrashed()
                ->findOrFail($coffee->id)
                ->current_stock,
        );
    }
    public function test_editing_order_to_higher_total_preserves_existing_payment_without_additional_payment(): void
    {
        $this->seedPermissions();

        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $oldProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Small Latte',
            'base_price' => 3.00,
        ]);

        $newProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Large Latte',
            'base_price' => 5.00,
        ]);

        $oldProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $newProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $oldProduct->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse
            ->assertStatus(201)
            ->assertJsonPath('data.total', 3);

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $newProduct->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('data.id', $orderId)
            ->assertJsonPath('data.total', 5);

        $this->assertDatabaseCount('payments', 1);

        $this->assertDatabaseHas('payments', [
            'order_id' => $orderId,
            'method' => 'cash',
            'amount' => 3,
            'tendered' => 3,
            'status' => 'completed',
            'processed_by' => $cashier->id,
        ]);

        $this->assertDatabaseCount('payment_refunds', 0);
    }
    public function test_editing_order_to_lower_total_preserves_existing_payment_without_refund(): void
    {
        $this->seedPermissions();

        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($branch->id, ['is_primary' => true]);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $oldProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Large Latte',
            'base_price' => 5.00,
        ]);

        $newProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Small Latte',
            'base_price' => 3.00,
        ]);

        $oldProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $newProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $oldProduct->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 5,
            ],
        ]);

        $createResponse
            ->assertStatus(201)
            ->assertJsonPath('data.total', 5);

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $newProduct->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('data.id', $orderId)
            ->assertJsonPath('data.total', 3);

        $this->assertDatabaseCount('payments', 1);

        $this->assertDatabaseHas('payments', [
            'order_id' => $orderId,
            'method' => 'cash',
            'amount' => 5,
            'tendered' => 5,
            'status' => 'completed',
            'processed_by' => $cashier->id,
        ]);

        $this->assertDatabaseCount('payment_refunds', 0);
    }
    public function test_admin_with_orders_edit_permission_can_edit_order(): void
    {
        $this->seedPermissions();

        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);

        $admin = User::factory()->create();
        $admin->assignRole('admin');
        $admin->branches()->attach($branch->id, ['is_primary' => true]);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $oldProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'Old Latte',
            'base_price' => 3.00,
        ]);

        $newProduct = Product::create([
            'category_id' => $category->id,
            'name' => 'New Latte',
            'base_price' => 3.00,
        ]);

        $oldProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $newProduct->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $oldProduct->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($admin)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $newProduct->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $orderId)
            ->assertJsonPath('data.total', 3);

        $this->assertSame(
            $newProduct->id,
            Order::withoutGlobalScopes()
                ->findOrFail($orderId)
                ->items()
                ->firstOrFail()
                ->product_id
        );
    }

    public function test_manager_cannot_edit_order_from_another_branch(): void
    {
        $this->seedPermissions();

        $orderBranch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $managerBranch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Downtown',
            'code' => 'PP-02',
        ]);

        $cashier = $this->makeCashier($orderBranch);

        $manager = User::factory()->create();
        $manager->assignRole('manager');
        $manager->branches()->attach($managerBranch->id, ['is_primary' => true]);

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.00,
        ]);

        $product->branches()->attach($orderBranch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
                'tendered' => 3,
            ],
        ]);

        $createResponse->assertStatus(201);

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($manager)->patchJson(
            "/api/v1/orders/{$orderId}",
            [
                'items' => [
                    [
                        'product_id' => $product->id,
                        'quantity' => 1,
                    ],
                ],
            ]
        );

        $response
            ->assertStatus(403)
            ->assertJsonPath('success', false);

        $this->assertSame(
            $product->id,
            Order::withoutGlobalScopes()
                ->findOrFail($orderId)
                ->items()
                ->firstOrFail()
                ->product_id
        );
    }
    public function test_order_listing_can_filter_split_payments(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        Permission::firstOrCreate([
            'name' => 'orders.view',
            'guard_name' => 'web',
        ]);

        $user->givePermissionTo('orders.view');

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Iced Latte',
            'base_price' => 10,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $createResponse = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'split',
                'payments' => [
                    [
                        'method' => 'cash',
                        'amount' => 4,
                        'tendered' => 5,
                    ],
                    [
                        'method' => 'qr',
                        'amount' => 6,
                    ],
                ],
            ],
        ]);

        $createResponse
            ->assertStatus(201)
            ->assertJsonPath('data.payment.method', 'split');

        $orderId = $createResponse->json('data.id');

        $response = $this->actingAs($user)->getJson(
            '/api/v1/orders?payment_method=split'
        );

        $response
            ->assertStatus(200)
            ->assertJsonPath('success', true);

        $orders = $response->json('data');

        $this->assertCount(1, $orders);
        $this->assertSame($orderId, $orders[0]['id']);
    }

    public function test_completed_order_awards_loyalty_points(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        Permission::firstOrCreate([
            'name' => 'loyalty.manage',
            'guard_name' => 'web',
        ]);

        $user->givePermissionTo('loyalty.manage');

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 5.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $customer = Customer::create([
            'branch_id' => $branch->id,
            'name' => 'Loyalty Customer',
            'phone' => '012345678',
        ]);

        LoyaltySetting::create([
            'branch_id' => $branch->id,
            'is_enabled' => true,
            'points_per_currency_unit' => 1,
            'points_per_reward_currency_unit' => 100,
            'minimum_redeem_points' => 100,
            'redemption_enabled' => true,
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'customer_id' => $customer->id,
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'payment' => ['method' => 'cash', 'tendered' => 10.00],
        ]);

        $response
            ->assertStatus(201)
            ->assertJsonPath('data.status', 'completed');

        $orderId = $response->json('data.id');

        $this->assertDatabaseHas('loyalty_transactions', [
            'customer_id' => $customer->id,
            'branch_id' => $branch->id,
            'order_id' => $orderId,
            'type' => 'earned',
            'points' => 5,
        ]);

        $transaction = LoyaltyTransaction::where('order_id', $orderId)->firstOrFail();
        $this->assertSame(5, (int) $transaction->balance_after);
    }


    public function test_paid_held_order_awards_loyalty_points(): void
    {
        $branch = Branch::create(['business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeCashier($branch);

        Permission::firstOrCreate([
            'name' => 'loyalty.manage',
            'guard_name' => 'web',
        ]);

        $user->givePermissionTo('loyalty.manage');

        $category = Category::create([
            'branch_id' => null,
            'name' => 'Coffee',
        ]);

        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 5.00,
        ]);

        $product->branches()->attach($branch->id, [
            'is_available' => true,
        ]);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $customer = Customer::create([
            'branch_id' => $branch->id,
            'name' => 'Held Loyalty Customer',
            'phone' => '012345679',
        ]);

        LoyaltySetting::create([
            'branch_id' => $branch->id,
            'is_enabled' => true,
            'points_per_currency_unit' => 1,
            'points_per_reward_currency_unit' => 100,
            'minimum_redeem_points' => 100,
            'redemption_enabled' => true,
        ]);

        $holdResponse = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'customer_id' => $customer->id,
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
        ]);

        $holdResponse
            ->assertStatus(201)
            ->assertJsonPath('data.status', 'held');

        $orderId = $holdResponse->json('data.id');

        $this->assertDatabaseHas('orders', [
            'id' => $orderId,
            'customer_id' => $customer->id,
            'status' => 'held',
        ]);

        $paymentResponse = $this->actingAs($user)->postJson(
            "/api/v1/orders/{$orderId}/pay",
            [
                'payment' => ['method' => 'cash', 'tendered' => 5.00],
            ],
        );

        $paymentResponse
            ->assertStatus(200)
            ->assertJsonPath('data.status', 'completed');

        $this->assertDatabaseHas('loyalty_transactions', [
            'customer_id' => $customer->id,
            'branch_id' => $branch->id,
            'order_id' => $orderId,
            'type' => 'earned',
            'points' => 5,
        ]);

        $transaction = LoyaltyTransaction::where('order_id', $orderId)->firstOrFail();
        $this->assertSame(5, (int) $transaction->balance_after);

        $this->assertSame('available', $table->fresh()->status);
    }

    private function makeHeldBillForPaymentReview(): array
    {
        $branch = Branch::create([
            'business_id' => $this->business->id,
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);
        $user = $this->makeCashier($branch);
        $category = Category::create(['name' => 'Coffee', 'branch_id' => null]);
        $product = Product::create([
            'category_id' => $category->id,
            'name' => 'Latte',
            'base_price' => 3.50,
        ]);
        $product->branches()->attach($branch->id, ['is_available' => true]);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);
        $customer = Customer::create([
            'branch_id' => $branch->id,
            'name' => 'Regular Customer',
        ]);
        $ingredient = $this->createIngredient($branch, $this->createUnit(), 'Coffee', 100);
        RecipeItem::create([
            'branch_id' => $branch->id,
            'product_id' => $product->id,
            'ingredient_id' => $ingredient->id,
            'quantity_used' => 10,
        ]);
        $held = $this->actingAs($user)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'customer_id' => $customer->id,
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
        ])->assertStatus(201);

        return [$held->json('data.id'), $product, $table, $customer, $ingredient];
    }

    public function test_saving_held_bill_preserves_customer_and_payment_uses_saved_items(): void
    {
        [$orderId, $product, $table, $customer, $ingredient] = $this->makeHeldBillForPaymentReview();

        $this->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertOk()->assertJsonPath('data.total', 7);

        $this->assertDatabaseHas('orders', [
            'id' => $orderId,
            'customer_id' => $customer->id,
        ]);
        $this->postJson("/api/v1/orders/{$orderId}/pay", [
            'expected_total' => 7,
            'payment' => ['method' => 'cash', 'tendered' => 10],
        ])->assertOk()->assertJsonPath('data.payment.amount', 7);

        $this->assertSame(80.0, (float) $ingredient->fresh()->current_stock);
        $this->assertSame('available', $table->fresh()->status);
    }

    public function test_held_payment_rejects_stale_total_without_changing_stock_or_table(): void
    {
        [$orderId, $product, $table, $customer, $ingredient] = $this->makeHeldBillForPaymentReview();
        $this->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertOk();

        $this->postJson("/api/v1/orders/{$orderId}/pay", [
            'expected_total' => 3.50,
            'payment' => ['method' => 'cash', 'tendered' => 10],
        ])->assertStatus(409)->assertJsonPath('success', false);

        $this->assertDatabaseHas('orders', ['id' => $orderId, 'status' => 'held']);
        $this->assertDatabaseMissing('payments', ['order_id' => $orderId]);
        $this->assertDatabaseMissing('stock_movements', [
            'reference_type' => Order::class,
            'reference_id' => $orderId,
            'type' => 'sale_deduction',
        ]);
        $this->assertSame(100.0, (float) $ingredient->fresh()->current_stock);
        $this->assertSame('occupied', $table->fresh()->status);
    }

    public function test_held_payment_rejects_invalid_expected_total(): void
    {
        [$orderId] = $this->makeHeldBillForPaymentReview();
        $this->postJson("/api/v1/orders/{$orderId}/pay", [
            'expected_total' => -1,
            'payment' => ['method' => 'cash', 'tendered' => 10],
        ])->assertStatus(422);
        $this->assertDatabaseMissing('payments', ['order_id' => $orderId]);
    }

}
