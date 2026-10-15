<?php

namespace Tests\Feature;

use App\Models\{Business, Branch, Category, Product, User};
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Str;
use Tests\TestCase;

class CheckoutControlsTest extends TestCase
{
    use RefreshDatabase;
    private User $actor;
    private Branch $branch;
    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $business = Business::factory()->create();
        $business->forceFill(['require_cash_shift' => true, 'require_manager_controls' => true])->save();
        $this->branch = Branch::factory()->create(['business_id' => $business->id]);
        $this->actor = User::factory()->create(['business_id' => $business->id]);
        $this->actor->assignRole('cashier');
        $this->actor->branches()->attach($this->branch->id);
        $this->actingAs($this->actor);
        $category = Category::create(['name' => 'Coffee', 'branch_id' => $this->branch->id]);
        $this->product = Product::create(['name' => 'Latte', 'category_id' => $category->id, 'base_price' => 10, 'is_active' => true]);
        $this->product->branches()->attach($this->branch->id, ['is_available' => true]);
    }

    private function payload(array $extra = []): array
    {
        return $extra + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'order_type' => 'takeaway', 'items' => [['product_id' => $this->product->id, 'quantity' => 1]],
            'payment' => ['method' => 'cash', 'tendered' => 10]];
    }

    private function open(): int
    {
        return $this->postJson('/api/v1/shifts', ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'opening_cash' => 20])->assertCreated()->json('data.id');
    }

    public function test_cash_without_shift_rolls_back_every_write(): void
    {
        foreach ([[], ['shift_id' => null], ['created_offline_at' => now()->toIso8601String()]] as $extra) {
            $this->postJson('/api/v1/orders', $this->payload($extra))->assertConflict();
        }
        foreach (['orders', 'order_items', 'payments', 'stock_movements'] as $table) $this->assertDatabaseCount($table, 0);
    }

    public function test_cash_replay_after_shift_close_does_not_create_another_sale(): void
    {
        $shift = $this->open();
        $input = $this->payload(['shift_id' => $shift]);
        $id = $this->postJson('/api/v1/orders', $input)->assertCreated()->json('data.id');
        $this->postJson('/api/v1/shifts/'.$shift.'/close', ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'counted_cash' => 30])->assertOk();
        $this->postJson('/api/v1/orders', $input)->assertCreated()->assertJsonPath('data.id', $id);
        $this->postJson('/api/v1/orders', $this->payload(['shift_id' => $shift]))->assertConflict();
        $this->assertDatabaseCount('payments', 1);
    }

    public function test_card_is_allowed_but_split_cash_requires_shift(): void
    {
        $this->postJson('/api/v1/orders', $this->payload(['payment' => ['method' => 'card']]))->assertCreated();
        $this->postJson('/api/v1/orders', $this->payload(['payment' => ['method' => 'split', 'payments' => [
            ['method' => 'card', 'amount' => 5], ['method' => 'cash', 'amount' => 5, 'tendered' => 5],
        ]]]))->assertConflict();
        $this->assertDatabaseCount('payments', 1);
    }

    public function test_cashier_cannot_approve_large_discount_but_manager_can_and_is_audited(): void
    {
        $this->open();
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 2]))->assertForbidden();
        $this->assertDatabaseCount('orders', 0);
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 1]))->assertCreated();
        $this->actor->syncRoles(['manager']);
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 2]))->assertCreated();
        $this->assertDatabaseHas('audit_logs', ['action' => 'order.discount_approved', 'user_id' => $this->actor->id]);
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 11]))->assertUnprocessable();
    }

    public function test_permission_alone_cannot_bypass_manager_refund_control(): void
    {
        $this->open();
        $id = $this->postJson('/api/v1/orders', $this->payload())->assertCreated()->json('data.id');
        $this->actor->givePermissionTo('orders.refund');
        $refund = ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'amount' => 2, 'reason' => 'Correction', 'inventory_disposition' => 'consumed'];
        $this->postJson('/api/v1/orders/'.$id.'/refund', $refund)->assertForbidden();
        $this->assertDatabaseCount('payment_refunds', 0);
        $this->actor->syncRoles(['manager']);
        $this->postJson('/api/v1/auth/manager-pin', ['expected_user_id' => $this->actor->id, 'current_password' => 'password', 'pin' => '836492', 'pin_confirmation' => '836492'])->assertOk();
        $this->withHeader('X-Manager-Pin', '836492')->postJson('/api/v1/orders/'.$id.'/refund', $refund)->assertOk();
        $this->withHeader('X-Manager-Pin', '836492')->postJson('/api/v1/orders/'.$id.'/refund', $refund)->assertOk();
        $this->assertDatabaseCount('payment_refunds', 1);
    }

    public function test_held_sale_requires_shift_at_payment_and_retains_manager_discount_approval(): void
    {
        $table = \App\Models\RestaurantTable::create(['branch_id' => $this->branch->id, 'name' => 'Table', 'capacity' => 2, 'status' => 'available', 'is_active' => true]);
        $input = $this->payload(['order_type' => 'dine_in', 'table_id' => $table->id, 'discount_total' => 2]);
        $this->postJson('/api/v1/orders/hold', $input + ['approved_by' => 999])->assertForbidden();
        $this->actor->syncRoles(['manager']);
        $id = $this->postJson('/api/v1/orders/hold', $input)->assertCreated()->json('data.id');
        $this->actor->syncRoles(['cashier']);
        $payment = ['branch_id' => $this->branch->id, 'payment' => ['method' => 'cash', 'tendered' => 8]];
        $this->postJson('/api/v1/orders/'.$id.'/pay', $payment)->assertConflict();
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'held']);
        $this->assertDatabaseCount('payments', 0);
        $this->open();
        $this->postJson('/api/v1/orders/'.$id.'/pay', $payment)->assertOk();
        $this->assertDatabaseCount('payments', 1);
        $this->assertDatabaseHas('audit_logs', ['action' => 'order.discount_approved', 'user_id' => $this->actor->id]);
    }


    public function test_split_payment_validates_persisted_cents_and_rolls_back_invalid_rows(): void
    {
        foreach ([[0.005, 9.995], [0.004, 9.996]] as [$first, $second]) {
            $this->postJson('/api/v1/orders', $this->payload(['payment' => [
                'method' => 'split', 'payments' => [
                    ['method' => 'card', 'amount' => $first],
                    ['method' => 'qr', 'amount' => $second],
                ],
            ]]))->assertUnprocessable();
            foreach (['orders', 'order_items', 'payments', 'stock_movements'] as $table) {
                $this->assertDatabaseCount($table, 0);
            }
        }

        $this->postJson('/api/v1/orders', $this->payload(['payment' => [
            'method' => 'split', 'payments' => [
                ['method' => 'card', 'amount' => 3.33],
                ['method' => 'qr', 'amount' => 6.67],
            ],
        ]]))->assertCreated();
        $this->assertDatabaseCount('payments', 2);
        $this->assertEquals(10, \App\Models\Payment::sum('amount'));
    }

    public function test_discount_cannot_exceed_subtotal_when_manager_controls_are_disabled(): void
    {
        $this->actor->business->forceFill(['require_manager_controls' => false])->save();
        $table = \App\Models\RestaurantTable::create(['branch_id' => $this->branch->id,
            'name' => 'Discount table', 'capacity' => 2, 'status' => 'available', 'is_active' => true]);
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 11,
            'payment' => ['method' => 'card']]))->assertUnprocessable();
        $this->postJson('/api/v1/orders/hold', $this->payload(['discount_total' => 11,
            'order_type' => 'dine_in', 'table_id' => $table->id]))->assertUnprocessable();
        foreach (['orders', 'order_items', 'payments', 'stock_movements'] as $name) {
            $this->assertDatabaseCount($name, 0);
        }
        $this->assertDatabaseHas('restaurant_tables', ['id' => $table->id, 'status' => 'available']);
        $this->postJson('/api/v1/orders', $this->payload(['discount_total' => 10,
            'payment' => ['method' => 'card']]))->assertCreated()->assertJsonPath('data.total', 0);
    }

    public function test_checkout_audit_failure_rolls_back_the_entire_sale(): void
    {
        $this->mock(\App\Services\AuditLogService::class, function ($mock) {
            $mock->shouldReceive('record')->andThrow(new \RuntimeException('Audit unavailable'));
        });
        $this->postJson('/api/v1/orders', $this->payload(['payment' => ['method' => 'card']]))
            ->assertStatus(500);
        foreach (['orders', 'order_items', 'payments', 'stock_movements'] as $name) {
            $this->assertDatabaseCount($name, 0);
        }
    }

    public function test_held_payment_loyalty_failure_preserves_the_unpaid_bill(): void
    {
        $table = \App\Models\RestaurantTable::create(['branch_id' => $this->branch->id,
            'name' => 'Atomic table', 'capacity' => 2, 'status' => 'available', 'is_active' => true]);
        $id = $this->postJson('/api/v1/orders/hold', $this->payload([
            'order_type' => 'dine_in', 'table_id' => $table->id]))->assertCreated()->json('data.id');
        $this->mock(\App\Services\LoyaltyService::class, function ($mock) {
            $mock->shouldReceive('awardForOrder')->andThrow(new \RuntimeException('Loyalty unavailable'));
        });
        $this->postJson('/api/v1/orders/'.$id.'/pay', ['payment' => ['method' => 'card']])
            ->assertStatus(500);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'held']);
        $this->assertDatabaseHas('restaurant_tables', ['id' => $table->id, 'status' => 'occupied']);
        $this->assertDatabaseCount('payments', 0);
        $this->assertDatabaseCount('stock_movements', 0);
        $this->assertDatabaseMissing('audit_logs', ['action' => 'order.paid']);
    }

    public function test_console_enable_is_business_specific_and_audited(): void
    {
        $other = Business::factory()->create();
        $this->assertSame(0, Artisan::call('pos:checkout-controls', ['business' => $other->id]));
        $this->assertFalse($other->fresh()->require_cash_shift);
        $this->assertSame(0, Artisan::call('pos:checkout-controls', ['business' => $other->id, '--enable' => true, '--discount-percent' => 5]));
        $this->assertTrue($other->fresh()->require_cash_shift);
        $this->assertEquals(5, $other->fresh()->manager_discount_percent);
        $this->assertDatabaseHas('audit_logs', ['business_id' => $other->id, 'action' => 'business.checkout_controls_enabled']);
        $this->assertSame(1, Artisan::call('pos:checkout-controls', ['business' => $other->id, '--enable' => true, '--discount-percent' => 101]));
    }
}
