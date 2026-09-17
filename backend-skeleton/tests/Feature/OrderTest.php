<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Ingredient;
use App\Models\Order;
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

    private function seedPermissions(): void
    {
        foreach (['orders.create', 'branches.view-all'] as $permission) {
            Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web']);
        }

        $cashier = Role::firstOrCreate(['name' => 'cashier', 'guard_name' => 'web']);
        $cashier->syncPermissions(['orders.create']);

        $admin = Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);
        $admin->syncPermissions(['orders.create', 'branches.view-all']);

        Role::firstOrCreate(['name' => 'manager', 'guard_name' => 'web']);
        // Deliberately no 'orders.create' synced to manager — matches the
        // real RolePermissionSeeder gap noted in OrderController's docblock.
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
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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
    }

    public function test_discount_total_reduces_the_final_total(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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

    public function test_an_unavailable_product_rejects_the_whole_order_and_creates_nothing(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
        $user = $this->makeCashier($branch);
        $category = Category::create(['branch_id' => null, 'name' => 'Coffee']);

        $validProduct = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 3.00]);
        $validProduct->branches()->attach($branch->id, ['is_available' => true]);

        // Only available at the OTHER branch — not sellable at $branch.
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

        // Critical: the transaction must have rolled back completely —
        // not even the valid line should exist.
        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('order_items', 0);
        $this->assertDatabaseCount('payments', 0);
    }

    public function test_explicit_branch_id_for_an_unassigned_branch_is_rejected(): void
    {
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
        $otherBranch = Branch::create(['name' => 'BKK1', 'code' => 'PP-02']);
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
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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
        $branch = Branch::create(['name' => 'Riverside', 'code' => 'PP-01']);
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
        $branch = Branch::create([
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
    }
    public function test_paid_held_dine_in_order_deducts_inventory(): void
    {
        $branch = Branch::create([
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
    public function test_paid_held_dine_in_order_rolls_back_when_inventory_is_insufficient(): void
    {
        $branch = Branch::create([
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
        $branch = Branch::create([
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
        $branch = Branch::create([
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
}
