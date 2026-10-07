<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Business;
use App\Models\Order;
use App\Models\KitchenTicket;
use App\Models\Payment;
use App\Models\RestaurantTable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Permission;
use Tests\TestCase;

class CancelHeldOrderTest extends TestCase
{
    use RefreshDatabase;

    private function setupOrder(string $status = 'held'): array
    {
        Permission::firstOrCreate(['name' => 'orders.cancel', 'guard_name' => 'web']);
        $business = Business::factory()->create();
        $branch = Branch::create([
            'business_id' => $business->id,
            'name' => 'Cancellation Branch',
            'code' => 'CAN-01',
        ]);
        $user = User::factory()->create();
        $user->branches()->attach($branch->id, ['is_primary' => true]);
        $table = RestaurantTable::create([
            'branch_id' => $branch->id,
            'name' => 'T1',
            'capacity' => 4,
            'status' => 'occupied',
            'is_active' => true,
        ]);
        $order = Order::create([
            'uuid' => (string) Str::uuid(),
            'branch_id' => $branch->id,
            'user_id' => $user->id,
            'table_id' => $table->id,
            'order_type' => 'dine_in',
            'status' => $status,
            'subtotal' => 5,
            'discount_total' => 0,
            'tax_total' => 0,
            'total' => 5,
        ]);

        return [$user, $order, $table];
    }

    public function test_authorized_cancel_preserves_order_and_releases_table(): void
    {
        [$user, $order, $table] = $this->setupOrder();
        $user->givePermissionTo('orders.cancel');

        $this->actingAs($user)
            ->postJson("/api/v1/orders/{$order->id}/cancel")
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled');

        $this->assertDatabaseHas('orders', ['id' => $order->id, 'status' => 'cancelled']);
        $this->assertDatabaseHas('restaurant_tables', ['id' => $table->id, 'status' => 'available']);
        $this->assertDatabaseCount('payments', 0);
        $this->postJson("/api/v1/orders/{$order->id}/cancel")->assertStatus(409);
    }

    public function test_cancel_updates_kitchen_tickets(): void
    {
        [$user, $order] = $this->setupOrder();
        $user->givePermissionTo('orders.cancel');
        $ticket = KitchenTicket::create(['order_id' => $order->id, 'status' => 'preparing']);
        $this->actingAs($user)->postJson("/api/v1/orders/{$order->id}/cancel")->assertOk();
        $this->assertDatabaseHas('kitchen_tickets', ['id' => $ticket->id, 'status' => 'cancelled']);
    }

    public function test_kitchen_acknowledgement_hides_ticket_but_keeps_history(): void
    {
        [$user, $order] = $this->setupOrder();
        $user->givePermissionTo('orders.cancel');
        $user->givePermissionTo(
            Permission::firstOrCreate(['name' => 'kitchen.update-status', 'guard_name' => 'web'])
        );
        $user->givePermissionTo(
            Permission::firstOrCreate(['name' => 'kitchen.view', 'guard_name' => 'web'])
        );
        $ticket = KitchenTicket::create(['order_id' => $order->id, 'status' => 'new']);
        $this->actingAs($user)->postJson("/api/v1/orders/{$order->id}/cancel")->assertOk();
        $this->postJson("/api/v1/kitchen/tickets/{$ticket->id}/acknowledge-cancellation")
            ->assertOk()
            ->assertJsonPath('data.acknowledged', true);
        $this->assertDatabaseHas('kitchen_tickets', ['id' => $ticket->id, 'status' => 'cancelled']);
        $this->assertNotNull($ticket->fresh()->cancellation_acknowledged_at);
        $this->getJson('/api/v1/kitchen/tickets')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_legacy_new_ticket_for_cancelled_order_can_be_acknowledged(): void
    {
        [$user, $order] = $this->setupOrder();
        $user->givePermissionTo(
            Permission::firstOrCreate(['name' => 'kitchen.update-status', 'guard_name' => 'web'])
        );
        $user->givePermissionTo(
            Permission::firstOrCreate(['name' => 'kitchen.view', 'guard_name' => 'web'])
        );
        $order->update(['status' => 'cancelled']);
        $ticket = KitchenTicket::create(['order_id' => $order->id, 'status' => 'new']);

        $this->actingAs($user)
            ->postJson("/api/v1/kitchen/tickets/{$ticket->id}/acknowledge-cancellation")
            ->assertOk();

        $this->assertDatabaseHas('kitchen_tickets', ['id' => $ticket->id, 'status' => 'cancelled']);
        $this->assertNotNull($ticket->fresh()->cancellation_acknowledged_at);
        $this->getJson('/api/v1/kitchen/tickets')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_non_cancelled_ticket_cannot_be_acknowledged(): void
    {
        [$user, $order] = $this->setupOrder();
        $user->givePermissionTo(
            Permission::firstOrCreate(['name' => 'kitchen.update-status', 'guard_name' => 'web'])
        );
        $ticket = KitchenTicket::create(['order_id' => $order->id, 'status' => 'new']);
        $this->actingAs($user)
            ->postJson("/api/v1/kitchen/tickets/{$ticket->id}/acknowledge-cancellation")
            ->assertStatus(409);
    }

    public function test_unauthorized_user_cannot_cancel(): void
    {
        [$user, $order, $table] = $this->setupOrder();

        $this->actingAs($user)
            ->postJson("/api/v1/orders/{$order->id}/cancel")
            ->assertForbidden();

        $this->assertDatabaseHas('orders', ['id' => $order->id, 'status' => 'held']);
        $this->assertDatabaseHas('restaurant_tables', ['id' => $table->id, 'status' => 'occupied']);
    }

    public function test_completed_order_cannot_be_cancelled(): void
    {
        [$user, $order, $table] = $this->setupOrder('completed');
        $user->givePermissionTo('orders.cancel');

        $this->actingAs($user)
            ->postJson("/api/v1/orders/{$order->id}/cancel")
            ->assertStatus(409);

        $this->assertDatabaseHas('restaurant_tables', ['id' => $table->id, 'status' => 'occupied']);
    }
}
