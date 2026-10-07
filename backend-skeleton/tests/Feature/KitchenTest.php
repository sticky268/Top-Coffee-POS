<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
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

    private function seedPermissions(): void
    {
        foreach ([
            'kitchen.view',
            'kitchen.update-status',
            'branches.view-all',
            'orders.create',
            'orders.cancel',
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
            'orders.cancel',
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

        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = User::factory()->create();

        $response = $this->actingAs($user)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        );

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_kitchen_user_can_view_tickets_for_assigned_branch(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

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
        $branchOne = $this->createBranch('Riverside', 'PP-01');

        $branchTwo = $this->createBranch('Downtown', 'PP-02');

        $user = $this->makeKitchenUser($branchOne);

        $response = $this->actingAs($user)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branchTwo->id
        );

        $response->assertStatus(403)
            ->assertJsonPath('success', false);
    }

    public function test_admin_can_view_another_branch(): void
    {
        $branch = $this->createBranch('Downtown', 'PP-02');

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
        $branch = $this->createBranch('Riverside', 'PP-01');

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
        $branch = $this->createBranch('Riverside', 'PP-01');

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
        $branch = $this->createBranch('Riverside', 'PP-01');

        $user = $this->makeKitchenUser($branch);

        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
            'sent_at' => now(),
        ]);

        $this->actingAs($user)->patchJson(
            '/api/v1/kitchen/tickets/' . $ticket->id . '/status',
            ['status' => 'preparing']
        )->assertOk();

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

    public function test_kitchen_status_transitions_must_be_sequential_and_cannot_repeat(): void
    {
        $branch = $this->createBranch('Transitions', 'KT-01');
        $user = $this->makeKitchenUser($branch);
        $ticket = KitchenTicket::create([
            'order_id' => $this->createOrder($branch, $user),
            'status' => 'new',
        ]);
        $url = '/api/v1/kitchen/tickets/' . $ticket->id . '/status';

        $this->actingAs($user)->patchJson($url, ['status' => 'ready'])->assertStatus(409);
        $this->assertSame('new', $ticket->fresh()->status);

        $this->patchJson($url, ['status' => 'preparing'])->assertOk();
        $this->patchJson($url, ['status' => 'preparing'])->assertStatus(409);
        $this->patchJson($url, ['status' => 'new'])->assertStatus(409);
        $this->patchJson($url, ['status' => 'completed'])->assertStatus(409);
        $this->assertSame('preparing', $ticket->fresh()->status);

        $this->patchJson($url, ['status' => 'ready'])->assertOk();
        $this->patchJson($url, ['status' => 'completed'])->assertOk();
        $this->patchJson($url, ['status' => 'preparing'])->assertStatus(409);
        $this->assertSame('completed', $ticket->fresh()->status);
        $this->assertNotNull($ticket->fresh()->completed_at);
    }

    public function test_invalid_kitchen_status_is_rejected(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');

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
        $branchOne = $this->createBranch('Riverside', 'PP-01');

        $branchTwo = $this->createBranch('Downtown', 'PP-02');

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

    public function test_adding_to_held_order_creates_a_separate_kitchen_ticket(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');
        $cashier = $this->makeCashier($branch);
        $product = $this->createProduct($branch);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id, 'name' => 'T1',
            'capacity' => 4, 'status' => 'available', 'is_active' => true,
        ]);

        $held = $this->actingAs($cashier)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in', 'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertStatus(201);
        $orderId = $held->json('data.id');
        $firstTicket = KitchenTicket::where('order_id', $orderId)->firstOrFail();
        $firstTicket->update(['status' => 'ready', 'ready_at' => now()]);

        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 3]],
        ])->assertStatus(200)->assertJsonPath('data.total', 10.5);

        $tickets = KitchenTicket::where('order_id', $orderId)->orderBy('id')->get();
        $this->assertCount(2, $tickets);
        $this->assertSame('ready', $tickets[0]->fresh()->status);
        $this->assertSame('new', $tickets[1]->status);
        $this->assertSame(2, (int) $tickets[0]->items()->sum('kitchen_ticket_items.quantity'));
        $this->assertSame(1, (int) $tickets[1]->items()->sum('kitchen_ticket_items.quantity'));

        // The kitchen API must preserve each ticket's original items even
        // after a subsequent batch is submitted for the same order.
        $kitchenUser = $this->makeKitchenUser($branch);
        $response = $this->actingAs($kitchenUser)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        )->assertOk();
        $ticketData = collect($response->json('data'))->keyBy('id');
        $this->assertCount(2, $ticketData);
        $this->assertSame(2, $ticketData[$tickets[0]->id]['order']['items'][0]['quantity']);
        $this->assertSame(1, $ticketData[$tickets[1]->id]['order']['items'][0]['quantity']);
        $this->assertSame($product->id, $ticketData[$tickets[0]->id]['order']['items'][0]['product_id']);
        $this->assertSame($product->id, $ticketData[$tickets[1]->id]['order']['items'][0]['product_id']);

        // Saving the same complete bill again must not generate another batch.
        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 3]],
        ])->assertStatus(200);
        $this->assertSame(2, KitchenTicket::where('order_id', $orderId)->count());
    }

    public function test_kitchen_api_preserves_original_product_when_new_product_is_added(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');
        $cashier = $this->makeCashier($branch);
        $latte = $this->createProduct($branch);
        $americano = Product::create([
            'category_id' => $latte->category_id,
            'name' => 'Americano',
            'base_price' => 2.50,
        ]);
        $americano->branches()->attach($branch->id, ['is_available' => true]);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id, 'name' => 'T1',
            'capacity' => 4, 'status' => 'available', 'is_active' => true,
        ]);

        $held = $this->actingAs($cashier)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in', 'table_id' => $table->id,
            'items' => [['product_id' => $latte->id, 'quantity' => 2]],
        ])->assertCreated();
        $orderId = $held->json('data.id');
        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [
                ['product_id' => $latte->id, 'quantity' => 2],
                ['product_id' => $americano->id, 'quantity' => 1],
            ],
        ])->assertOk();

        $tickets = KitchenTicket::where('order_id', $orderId)->orderBy('id')->get();
        $this->assertCount(2, $tickets);
        $kitchenUser = $this->makeKitchenUser($branch);
        $response = $this->actingAs($kitchenUser)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        )->assertOk();
        $byId = collect($response->json('data'))->keyBy('id');
        $this->assertCount(1, $byId[$tickets[0]->id]['order']['items']);
        $this->assertCount(1, $byId[$tickets[1]->id]['order']['items']);
        $this->assertSame($latte->id, $byId[$tickets[0]->id]['order']['items'][0]['product_id']);
        $this->assertSame(2, $byId[$tickets[0]->id]['order']['items'][0]['quantity']);
        $this->assertSame($americano->id, $byId[$tickets[1]->id]['order']['items'][0]['product_id']);
        $this->assertSame(1, $byId[$tickets[1]->id]['order']['items'][0]['quantity']);
    }

    public function test_held_order_rejects_reducing_already_submitted_quantities(): void
    {
        $branch = $this->createBranch('Riverside', 'PP-01');
        $cashier = $this->makeCashier($branch);
        $product = $this->createProduct($branch);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id, 'name' => 'T1',
            'capacity' => 4, 'status' => 'available', 'is_active' => true,
        ]);
        $held = $this->actingAs($cashier)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in', 'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertStatus(201);
        $orderId = $held->json('data.id');

        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
        ])->assertStatus(403);

        $this->assertSame(1, KitchenTicket::where('order_id', $orderId)->count());
        $this->assertSame(2, (int) \App\Models\OrderItem::where('order_id', $orderId)->sum('quantity'));
    }

    public function test_kitchen_display_can_be_disabled_per_branch(): void
    {
        $branch = $this->createBranch('No KDS', 'NK-01');
        $branch->update(['use_kitchen_display' => false]);
        $cashier = $this->makeCashier($branch);
        $product = $this->createProduct($branch);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $held = $this->actingAs($cashier)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertCreated();

        $orderId = $held->json('data.id');
        $this->assertSame(0, KitchenTicket::where('order_id', $orderId)->count());

        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
        ])->assertOk()->assertJsonPath('data.total', 3.5);

        $this->assertSame(1, (int) \App\Models\OrderItem::where('order_id', $orderId)->sum('quantity'));
        $this->assertSame(0, KitchenTicket::where('order_id', $orderId)->count());

        $kitchenUser = $this->makeKitchenUser($branch);
        $this->actingAs($kitchenUser)
            ->getJson('/api/v1/kitchen/tickets?branch_id=' . $branch->id)
            ->assertOk()
            ->assertJsonPath('kitchen_enabled', false)
            ->assertJsonCount(0, 'data');
    }

    public function test_authorized_void_creates_kitchen_cancellation_ticket_and_preserves_original_batch(): void
    {
        $branch = $this->createBranch('Void KDS', 'VK-01');
        $cashier = $this->makeCashier($branch);
        $cashier->givePermissionTo('orders.cancel');
        $product = $this->createProduct($branch);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'available',
            'is_active' => true,
        ]);

        $held = $this->actingAs($cashier)->postJson('/api/v1/orders/hold', [
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'quantity' => 2]],
        ])->assertCreated();

        $orderId = $held->json('data.id');
        $original = KitchenTicket::where('order_id', $orderId)->firstOrFail();

        $this->actingAs($cashier)->patchJson("/api/v1/orders/{$orderId}/hold", [
            'items' => [['product_id' => $product->id, 'quantity' => 1]],
            'void_reason' => 'Customer changed mind',
        ])->assertOk()->assertJsonPath('data.total', 3.5);

        $tickets = KitchenTicket::where('order_id', $orderId)->orderBy('id')->get();
        $this->assertCount(2, $tickets);
        $this->assertSame('new', $tickets[0]->status);
        $this->assertSame('cancelled', $tickets[1]->status);
        $this->assertSame('Customer changed mind', $tickets[1]->cancellation_reason);
        $this->assertSame($cashier->id, $tickets[1]->cancelled_by);
        $this->assertSame(2, (int) $original->items()->sum('kitchen_ticket_items.quantity'));
        $this->assertSame(1, (int) $tickets[1]->items()->sum('kitchen_ticket_items.quantity'));
        $this->assertSame(1, (int) \App\Models\OrderItem::where('order_id', $orderId)->sum('quantity'));
        $this->assertDatabaseHas('kitchen_item_voids', [
            'order_id' => $orderId,
            'order_number' => $held->json('data.order_number'),
            'order_item_id' => $original->items()->firstOrFail()->id,
            'kitchen_ticket_id' => $original->id,
            'quantity' => 1,
            'reason' => 'Customer changed mind',
            'kitchen_status' => 'new',
            'voided_by' => $cashier->id,
        ]);

        $kitchenUser = $this->makeKitchenUser($branch);
        $response = $this->actingAs($kitchenUser)->getJson(
            '/api/v1/kitchen/tickets?branch_id=' . $branch->id
        )->assertOk();

        $voidTicket = collect($response->json('data'))->firstWhere('id', $tickets[1]->id);
        $this->assertSame('cancelled', $voidTicket['status']);
        $this->assertSame('Customer changed mind', $voidTicket['cancellation_reason']);
        $this->assertSame(1, $voidTicket['order']['items'][0]['quantity']);

        $this->actingAs($kitchenUser)
            ->postJson('/api/v1/kitchen/tickets/' . $tickets[1]->id . '/acknowledge-cancellation')
            ->assertOk()
            ->assertJsonPath('data.acknowledged', true);
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
