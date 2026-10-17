<?php

namespace Tests\Feature;

use App\Models\{Branch, Business, Order, Payment, RestaurantTable, User};
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\{Artisan, DB, Hash};
use Illuminate\Support\Str;
use Tests\TestCase;

class ManagerPinTest extends TestCase
{
    use RefreshDatabase;
    private User $manager;
    private Branch $branch;
    private Order $order;
    private RestaurantTable $table;
    private const PIN = '836492'; // Synthetic test credential, never an owner PIN.

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $business = Business::factory()->create();
        $business->forceFill(['require_manager_controls' => true, 'require_cash_shift' => true, 'manager_discount_percent' => 0])->save();
        $this->branch = Branch::factory()->create(['business_id' => $business->id]);
        $this->manager = User::factory()->create(['business_id' => $business->id, 'password' => Hash::make('test-account-password')]);
        $this->manager->assignRole('manager');
        $this->manager->branches()->attach($this->branch->id);
        $this->actingAs($this->manager);
        $this->table = RestaurantTable::create(['branch_id' => $this->branch->id, 'name' => 'PIN test', 'capacity' => 2, 'status' => 'occupied', 'is_active' => true]);
        $this->order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'user_id' => $this->manager->id, 'table_id' => $this->table->id, 'order_type' => 'dine_in',
            'status' => 'held', 'subtotal' => 10, 'discount_total' => 0, 'tax_total' => 0, 'total' => 10]);
    }

    private function enrollment(array $extra = []): array
    {
        return $extra + ['expected_user_id' => $this->manager->id, 'current_password' => 'test-account-password', 'pin' => self::PIN, 'pin_confirmation' => self::PIN];
    }

    private function enroll(): void
    {
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment())->assertOk();
    }

    private function refund(array $extra = []): array
    {
        return $extra + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id, 'amount' => 2,
            'reason' => 'Test correction', 'inventory_disposition' => 'consumed'];
    }

    private function paid(): void
    {
        $this->order->forceFill(['status' => 'completed'])->save();
        Payment::create(['order_id' => $this->order->id, 'method' => 'card', 'amount' => 10, 'status' => 'completed', 'processed_by' => $this->manager->id]);
    }

    public function test_enrollment_requires_own_password_and_never_serializes_pin_or_hash(): void
    {
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment(['current_password' => 'wrong']))->assertForbidden();
        $this->assertNull($this->manager->fresh()->manager_pin_hash);
        $this->enroll();
        $hash = $this->manager->fresh()->manager_pin_hash;
        $this->assertNotSame(self::PIN, $hash);
        $this->assertFalse(Hash::check(self::PIN, $hash)); // DB-only attacker lacks APP_KEY pepper.
        $this->getJson('/api/v1/auth/manager-pin')->assertOk()->assertJsonPath('data.configured', true);
        foreach ([$this->manager->fresh()->toJson(), json_encode(DB::table('audit_logs')->get())] as $json) {
            $this->assertStringNotContainsString(self::PIN, $json);
            $this->assertStringNotContainsString($hash, $json);
            $this->assertStringNotContainsString('test-account-password', $json);
        }
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.manager_pin_changed', 'user_id' => $this->manager->id]);
    }

    public function test_cashier_cannot_enroll_or_approve_even_with_manager_pin_and_permission(): void
    {
        $this->enroll();
        $this->manager->syncRoles(['cashier']);
        $this->manager->givePermissionTo(['orders.cancel', 'orders.refund']);
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment())->assertForbidden();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertForbidden();
        $this->assertDatabaseHas('orders', ['id' => $this->order->id, 'status' => 'held']);
    }

    public function test_missing_or_wrong_pin_cannot_void_and_valid_pin_audits_atomically(): void
    {
        $this->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertConflict();
        $this->enroll();
        $this->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertUnprocessable();
        $this->withHeader('X-Manager-Pin', '928374')->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertForbidden();
        $this->assertSame(1, (int) $this->manager->fresh()->manager_pin_failures);
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertOk();
        $this->assertDatabaseHas('orders', ['id' => $this->order->id, 'status' => 'cancelled']);
        $this->assertDatabaseHas('restaurant_tables', ['id' => $this->table->id, 'status' => 'available']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'order.manager_pin_approved']);
        $this->assertSame(0, (int) $this->manager->fresh()->manager_pin_failures);
    }

    public function test_lockout_survives_retries_and_pin_reenrollment_cannot_bypass_wait(): void
    {
        $this->enroll();
        for ($i = 0; $i < 5; $i++) {
            $response = $this->withHeader('X-Manager-Pin', '928374')->postJson('/api/v1/orders/'.$this->order->id.'/cancel');
            $response->assertStatus($i === 4 ? 429 : 403);
        }
        $this->assertSame(5, (int) $this->manager->fresh()->manager_pin_failures);
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment())->assertStatus(429);
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertStatus(429);
        $this->assertSame(5, DB::table('audit_logs')->where('action', 'auth.manager_pin_failed')->count());
        $this->travel(16)->minutes();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertOk();
    }

    public function test_refund_replay_needs_pin_again_but_has_one_financial_effect(): void
    {
        $this->paid(); $this->enroll();
        $input = $this->refund();
        $this->postJson('/api/v1/orders/'.$this->order->id.'/refund', $input)->assertUnprocessable();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/refund', $input)->assertOk();
        $this->withHeader('X-Manager-Pin', '928374')->postJson('/api/v1/orders/'.$this->order->id.'/refund', $input)->assertForbidden();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/refund', $input)->assertOk();
        $this->assertDatabaseCount('payment_refunds', 1);
        $this->assertSame(1, DB::table('audit_logs')->where('action', 'order.manager_pin_approved')->count());
        $this->assertStringNotContainsString(self::PIN, json_encode(DB::table('operation_requests')->get()));
    }

    public function test_foreign_branch_or_business_does_not_consume_pin_attempts(): void
    {
        $this->enroll();
        foreach ([$this->manager->business_id, Business::factory()->create()->id] as $businessId) {
            $branch = Branch::factory()->create(['business_id' => $businessId]);
            $order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $branch->id, 'user_id' => $this->manager->id,
                'order_type' => 'dine_in', 'status' => 'held', 'subtotal' => 0, 'total' => 0, 'tax_total' => 0, 'discount_total' => 0]);
            $response = $this->withHeader('X-Manager-Pin', '928374')->postJson('/api/v1/orders/'.$order->id.'/cancel');
            $this->assertContains($response->status(), [403, 404]);
        }
        $this->assertSame(0, (int) $this->manager->fresh()->manager_pin_failures);
    }

    public function test_new_pin_invalidates_old_pin_and_cannot_change_another_user(): void
    {
        $this->enroll();
        $other = User::factory()->create(['business_id' => $this->manager->business_id]);
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment(['expected_user_id' => $other->id]))->assertForbidden();
        $this->postJson('/api/v1/auth/manager-pin', $this->enrollment(['pin' => '749281', 'pin_confirmation' => '749281']))->assertOk();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertForbidden();
        $this->withHeader('X-Manager-Pin', '749281')->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertOk();
    }

    public function test_readiness_passes_only_after_real_enrollment_and_branch_coverage(): void
    {
        Business::where('id', '!=', $this->manager->business_id)->update(['is_active' => false]);
        config(['payments.allowed_methods' => ['cash']]);
        $this->assertSame(1, Artisan::call('pos:business-settings-check', ['--json' => true]));
        $this->enroll();
        $this->assertSame(0, Artisan::call('pos:business-settings-check', ['--json' => true]));
        Branch::factory()->create(['business_id' => $this->manager->business_id]);
        $this->assertSame(1, Artisan::call('pos:business-settings-check', ['--json' => true]));
    }

    public function test_production_enforces_pin_even_if_business_manager_controls_are_disabled(): void
    {
        $this->enroll();
        $this->manager->business->forceFill(['require_manager_controls' => false])->save();
        config(['app.env' => 'production']);
        $this->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertUnprocessable();
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertOk();
    }

    public function test_trivial_pins_and_missing_permissions_cannot_approve(): void
    {
        foreach (['111111', '123456', '654321'] as $pin) {
            $this->postJson('/api/v1/auth/manager-pin', $this->enrollment(['pin' => $pin, 'pin_confirmation' => $pin]))->assertUnprocessable();
        }
        $this->enroll();
        $this->manager->syncRoles([]);
        $this->manager->assignRole(\Spatie\Permission\Models\Role::create(['name' => 'restricted-manager', 'guard_name' => 'web']));
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertForbidden();
        $this->assertDatabaseCount('payment_refunds', 0);
    }

    public function test_cancel_audit_failure_rolls_back_order_and_table(): void
    {
        $this->enroll();
        $this->mock(\App\Services\AuditLogService::class)->shouldReceive('record')->andThrow(new \RuntimeException('Audit unavailable'));
        $this->withHeader('X-Manager-Pin', self::PIN)->postJson('/api/v1/orders/'.$this->order->id.'/cancel')->assertStatus(500);
        $this->assertDatabaseHas('orders', ['id' => $this->order->id, 'status' => 'held']);
        $this->assertDatabaseHas('restaurant_tables', ['id' => $this->table->id, 'status' => 'occupied']);
    }
}
