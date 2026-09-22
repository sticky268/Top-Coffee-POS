<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Category;
use App\Models\KitchenTicket;
use App\Models\Product;
use App\Models\RestaurantTable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class KitchenTest extends TestCase
{
    use RefreshDatabase;

    private function seedPermissions(): void
    {
        foreach ([
            'kitchen.view',
            'kitchen.update-status',
            'branches.view-all',
            'orders.create',
        ] as $permission) {
            Permission::firstOrCreate([
                'name' => $permission,
                'guard_name' => 'web',
            ]);
        }

        $kitchen = Role::firstOrCreate([
            'name' => 'kitchen_staff',
            'guard_name' => 'web',
        ]);

        $kitchen->syncPermissions([
            'kitchen.view',
            'kitchen.update-status',
        ]);

        $admin = Role::firstOrCreate([
            'name' => 'admin',
            'guard_name' => 'web',
        ]);

        $admin->syncPermissions([
            'kitchen.view',
            'kitchen.update-status',
            'branches.view-all',
            'orders.create',
        ]);

        $cashier = Role::firstOrCreate([
            'name' => 'cashier',
            'guard_name' => 'web',
        ]);

        $cashier->syncPermissions([
            'orders.create',
        ]);
    }

    private function makeKitchenUser(Branch $branch): User
    {
        $this->seedPermissions();

        $user = User::factory()->create();
        $user->assignRole('kitchen_staff');

        $user->branches()->attach($branch->id, [
            'is_primary' => true,
        ]);

        return $user;
    }

    private function makeAdminUser(): User
    {
        $this->seedPermissions();

        $user = User::factory()->create();
        $user->assignRole('admin');

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

    private function createProduct(Branch $branch): Product
    {
        $category = Category::create([
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

        return $product;
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/v1/kitchen/tickets')
            ->assertStatus(401);

        $this->patchJson('/api/v1/kitchen/tickets/1/status', [
            'status' => 'preparing',
        ])->assertStatus(401);
    }

    public function test_user_without_kitchen_view_permission_is_rejected(): void
    {
        $this->seedPermissions();

        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = User::factory()->create();

        $response = $this->actingAs($user)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        );

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_kitchen_user_can_view_tickets_for_assigned_branch(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeKitchenUser($branch);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($user)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        );

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.0.id', $ticket->id)
            ->assertJsonPath('data.0.status', 'new');
    }

    public function test_kitchen_user_cannot_view_another_branch(): void
    {
        $branchOne = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branchTwo = Branch::create([
            'name' => 'Downtown',
            'code' => 'PP-02',
        ]);

        $user = $this->makeKitchenUser($branchOne);

        $response = $this->actingAs($user)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branchTwo->id
        );

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_admin_can_view_another_branch(): void
    {
        $branch = Branch::create([
            'name' => 'Downtown',
            'code' => 'PP-02',
        ]);

        $admin = $this->makeAdminUser();

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $admin),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($admin)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        );

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.0.id', $ticket->id);
    }

    public function test_creating_an_order_creates_a_kitchen_ticket(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $cashier = $this->makeCashier($branch);
        $product = $this->createProduct($branch);

        $response = $this->actingAs($cashier)->postJson('/api/v1/orders', [
            'order_type' => 'takeaway',
            'items' => [
                [
                    'product_id' => $product->id,
                    'product_variant_id' => null,
                    'quantity' => 1,
                ],
            ],
            'payment' => [
                'method' => 'cash',
            ],
        ]);

        $response->assertStatus(201);

        $orderId = $response->json('data.id');

        $this->assertDatabaseHas('kitchen_tickets', [
            'order_id' => $orderId,
            'status' => 'new',
        ]);
    }

    public function test_kitchen_ticket_status_can_be_updated(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeKitchenUser($branch);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'preparing']
        );

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $ticket->id)
            ->assertJsonPath('data.status', 'preparing');

        $this->assertDatabaseHas('kitchen_tickets', [
            'id' => $ticket->id,
            'status' => 'preparing',
        ]);
    }

    public function test_kitchen_ticket_status_updates_timestamps(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeKitchenUser($branch);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'ready']
        )->assertStatus(200);

        $ticket->refresh();

        $this->assertNotNull($ticket->sent_at);
        $this->assertNotNull($ticket->ready_at);
        $this->assertNull($ticket->completed_at);

        $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'completed']
        )->assertStatus(200);

        $ticket->refresh();

        $this->assertNotNull($ticket->sent_at);
        $this->assertNotNull($ticket->ready_at);
        $this->assertNotNull($ticket->completed_at);
    }

    public function test_invalid_kitchen_status_is_rejected(): void
    {
        $branch = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $user = $this->makeKitchenUser($branch);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'invalid-status']
        );

        $response->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_kitchen_user_cannot_update_ticket_from_another_branch(): void
    {
        $branchOne = Branch::create([
            'name' => 'Riverside',
            'code' => 'PP-01',
        ]);

        $branchTwo = Branch::create([
            'name' => 'Downtown',
            'code' => 'PP-02',
        ]);

        $user = $this->makeKitchenUser($branchOne);
        $branchTwoUser = $this->makeKitchenUser($branchTwo);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branchTwo, $branchTwoUser),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'preparing']
        );

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    private function createOrder(Branch $branch, User $user): int
    {
        $product = $this->createProduct($branch);

        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
        ]);

        $orderId = \App\Models\Order::create([
            'uuid' => (string) \Illuminate\Support\Str::uuid(),
            'branch_id' => $branch->id,
            'user_id' => $user->id,
            'table_id' => $table->id,
            'order_type' => 'dine_in',
            'status' => 'completed',
            'subtotal' => 3.50,
            'discount_amount' => 0,
            'total' => 3.50,
        ])->id;

        \App\Models\OrderItem::create([
            'order_id' => $orderId,
            'product_id' => $product->id,
            'quantity' => 1,
            'unit_price' => 3.50,
            'line_total' => 3.50,
        ]);

        return $orderId;
    }
}
