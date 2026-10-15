<?php

namespace Tests\Feature;

use App\Models\{AuditLog, Branch, Business, Category, Order, Payment, Product, User};
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\{Auth, DB};
use Illuminate\Support\Str;
use Tests\TestCase;

class SecurityAttackPathsTest extends TestCase
{
    use RefreshDatabase;
    private User $cashier;
    private Branch $branch;
    private Branch $other;
    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $business = Business::factory()->create();
        $business->forceFill(['require_manager_controls' => true, 'manager_discount_percent' => 0])->save();
        $this->branch = Branch::factory()->create(['business_id' => $business->id]);
        $this->other = Branch::factory()->create(['business_id' => $business->id]);
        $this->cashier = User::factory()->create(['business_id' => $business->id, 'password' => bcrypt('fixture-password')]);
        $this->cashier->assignRole('cashier');
        $this->cashier->branches()->attach($this->branch);
        $category = Category::create(['branch_id' => $this->branch->id, 'name' => 'Coffee']);
        $this->product = Product::create(['category_id' => $category->id, 'name' => 'Latte', 'base_price' => 10, 'is_active' => true]);
        $this->product->branches()->attach($this->branch, ['is_available' => true]);
    }

    private function bearer(?string $token = null): static
    {
        Auth::forgetGuards();
        return $this->withToken($token ?? $this->cashier->createToken('fixture')->plainTextToken);
    }

    private function sale(array $extra = []): array
    {
        return $extra + ['uuid' => (string) Str::uuid(), 'branch_id' => $this->branch->id,
            'expected_cashier_id' => $this->cashier->id, 'order_type' => 'takeaway',
            'items' => [['product_id' => $this->product->id, 'quantity' => 1]],
            'payment' => ['method' => 'qr']];
    }

    public function test_cashier_with_refund_permission_cannot_refund_another_branch_using_either_branch_id(): void
    {
        $this->cashier->givePermissionTo('orders.refund');
        $order = Order::create(['uuid' => (string) Str::uuid(), 'branch_id' => $this->other->id,
            'user_id' => $this->cashier->id, 'order_type' => 'takeaway', 'status' => 'completed', 'subtotal' => 10, 'total' => 10]);
        Payment::create(['order_id' => $order->id, 'method' => 'qr', 'amount' => 10, 'status' => 'completed', 'processed_by' => $this->cashier->id]);
        $input = ['uuid' => (string) Str::uuid(), 'amount' => 1, 'reason' => 'Fraud attempt', 'inventory_disposition' => 'consumed'];
        $this->bearer()->postJson('/api/v1/orders/'.$order->id.'/refund', $input + ['branch_id' => $this->other->id])->assertForbidden();
        $this->bearer()->postJson('/api/v1/orders/'.$order->id.'/refund', $input + ['branch_id' => $this->branch->id])->assertNotFound();
        $this->assertDatabaseCount('payment_refunds', 0);
        $this->assertDatabaseCount('stock_movements', 0);
        $this->assertDatabaseHas('payments', ['order_id' => $order->id, 'amount' => 10, 'status' => 'completed']);
    }

    public function test_tampered_expected_total_rolls_back_and_extra_client_prices_never_settle_the_sale(): void
    {
        $this->bearer()->postJson('/api/v1/orders', $this->sale(['expected_total' => 0.01]))->assertConflict();
        $this->assertDatabaseCount('orders', 0);
        $input = $this->sale(['total' => 0.01, 'subtotal' => 0.01, 'tax_total' => -100,
            'items' => [['product_id' => $this->product->id, 'quantity' => 1, 'unit_price' => 0.01]],
            'payment' => ['method' => 'qr', 'amount' => 0.01]]);
        $id = $this->bearer()->postJson('/api/v1/orders', $input)->assertCreated()->json('data.id');
        $this->assertDatabaseHas('orders', ['id' => $id, 'total' => 10, 'tax_total' => 0]);
        $this->assertDatabaseHas('payments', ['order_id' => $id, 'amount' => 10]);
    }

    public function test_same_offline_uuid_records_once_and_changed_content_or_actor_is_rejected(): void
    {
        $input = $this->sale(['created_offline_at' => '2000-01-01T00:00:00Z']);
        $id = $this->bearer()->postJson('/api/v1/orders', $input)->assertCreated()->json('data.id');
        $this->bearer()->postJson('/api/v1/orders', $input)->assertCreated()->assertJsonPath('data.id', $id);
        $this->bearer()->postJson('/api/v1/orders', array_replace($input, ['discount_total' => 1]))->assertConflict();
        $peer = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $peer->assignRole('cashier'); $peer->branches()->attach($this->branch);
        $input['expected_cashier_id'] = $peer->id;
        $this->bearer($peer->createToken('peer')->plainTextToken)->postJson('/api/v1/orders', $input)->assertConflict();
        $this->assertDatabaseCount('orders', 1);
        $this->assertDatabaseCount('payments', 1);
        $this->assertTrue(Order::withoutGlobalScopes()->find($id)->completed_at->isToday());
    }

    public function test_cashier_token_cannot_call_manager_endpoints_or_reset_its_role(): void
    {
        $this->bearer()->getJson('/api/v1/users')->assertForbidden();
        $this->bearer()->getJson('/api/v1/reports?branch_id='.$this->branch->id)->assertForbidden();
        $this->bearer()->patchJson('/api/v1/users/'.$this->cashier->id, ['role' => 'admin', 'branch_ids' => [$this->other->id]])->assertForbidden();
        $this->assertTrue($this->cashier->fresh()->hasRole('cashier'));
        $this->assertFalse($this->cashier->fresh()->hasRole('admin'));
    }

    public function test_own_sessions_never_expose_token_hashes_or_other_users_sessions_and_revocation_stops_api_access(): void
    {
        $lost = $this->cashier->createToken('lost-tablet');
        $current = $this->cashier->createToken('owner-device');
        $peer = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $foreign = $peer->createToken('foreign');
        $response = $this->bearer($current->plainTextToken)->getJson('/api/v1/auth/sessions')->assertOk();
        $this->assertCount(2, $response->json('data'));
        $this->assertArrayNotHasKey('token', $response->json('data.0'));
        $this->assertStringNotContainsString($lost->accessToken->token, $response->getContent());
        $this->bearer($current->plainTextToken)->deleteJson('/api/v1/auth/sessions/'.$foreign->accessToken->id)->assertNotFound();
        $this->bearer($current->plainTextToken)->deleteJson('/api/v1/auth/sessions/'.$lost->accessToken->id)->assertOk();
        $this->bearer($lost->plainTextToken)->getJson('/api/v1/auth/me')->assertUnauthorized();
        $this->bearer($current->plainTextToken)->getJson('/api/v1/auth/me')->assertOk();
    }

    public function test_password_login_rotates_only_this_installation_and_expires_within_twelve_hours(): void
    {
        $device = (string) Str::uuid();
        $payload = ['email' => $this->cashier->email, 'password' => 'fixture-password', 'device_name' => 'Tablet', 'device_id' => $device];
        $first = $this->postJson('/api/v1/auth/login', $payload)->assertOk()->json('data.token');
        $second = $this->postJson('/api/v1/auth/login', $payload)->assertOk()->json('data.token');
        $this->assertSame(1, $this->cashier->tokens()->count());
        $this->assertNotNull($this->cashier->tokens()->first()->expires_at);
        $this->assertLessThanOrEqual(720, now()->diffInMinutes($this->cashier->tokens()->first()->expires_at));
        $this->bearer($first)->getJson('/api/v1/auth/me')->assertUnauthorized();
        $this->bearer($second)->getJson('/api/v1/auth/me')->assertOk();
        $this->cashier->tokens()->update(['expires_at' => now()->subSecond()]);
        $this->bearer($second)->getJson('/api/v1/auth/me')->assertUnauthorized();
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.login_succeeded', 'user_id' => $this->cashier->id]);
    }

    public function test_revocation_works_even_when_subscription_expired(): void
    {
        $token = $this->cashier->createToken('expired-subscription')->plainTextToken;
        $this->cashier->business->forceFill(['expires_at' => now()->subDay()])->save();
        $this->bearer($token)->postJson('/api/v1/auth/logout-all')->assertOk();
        $this->bearer($token)->getJson('/api/v1/auth/me')->assertUnauthorized();
    }

    public function test_manager_can_revoke_assigned_cashier_but_not_another_branch_or_business(): void
    {
        $manager = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $manager->assignRole('manager'); $manager->branches()->attach($this->branch);
        $token = $manager->createToken('manager')->plainTextToken;
        $this->cashier->createToken('stolen');
        $this->bearer($token)->postJson('/api/v1/users/'.$this->cashier->id.'/revoke-sessions')->assertOk();
        $this->assertSame(0, $this->cashier->tokens()->count());
        $peer = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $peer->assignRole('cashier'); $peer->branches()->attach($this->other);
        $this->bearer($token)->postJson('/api/v1/users/'.$peer->id.'/revoke-sessions')->assertForbidden();
        $foreign = User::factory()->create();
        $this->bearer($token)->postJson('/api/v1/users/'.$foreign->id.'/revoke-sessions')->assertForbidden();
    }

    public function test_failed_passwords_are_audited_without_secrets_and_account_throttle_survives_ip_changes(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.'.($i + 1)])
                ->postJson('/api/v1/auth/login', ['email' => $this->cashier->email, 'password' => 'wrong-secret', 'device_name' => 'probe'])->assertUnauthorized();
        }
        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.99'])->postJson('/api/v1/auth/login',
            ['email' => strtoupper($this->cashier->email), 'password' => 'wrong-secret', 'device_name' => 'probe'])->assertTooManyRequests();
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $this->assertDatabaseCount('audit_logs', 10);
        $this->assertStringNotContainsString('wrong-secret', AuditLog::withoutGlobalScopes()->get()->toJson());
    }

    public function test_scoped_manager_cannot_change_a_shared_global_price_but_can_change_own_branch_override(): void
    {
        $this->product->branches()->attach($this->other, ['is_available' => true]);
        $manager = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $manager->assignRole('manager'); $manager->branches()->attach($this->branch);
        $token = $manager->createToken('scoped-manager')->plainTextToken;
        $this->bearer($token)->patchJson('/api/v1/products/'.$this->product->id, ['base_price' => 0.01])->assertForbidden();
        $this->assertDatabaseHas('products', ['id' => $this->product->id, 'base_price' => 10]);
        $this->bearer($token)->patchJson('/api/v1/products/'.$this->product->id,
            ['branches' => [['branch_id' => $this->branch->id, 'price_override' => 9]]])->assertOk();
        $this->assertDatabaseHas('branch_product', ['product_id' => $this->product->id, 'branch_id' => $this->branch->id, 'price_override' => 9]);
        $this->assertDatabaseHas('branch_product', ['product_id' => $this->product->id, 'branch_id' => $this->other->id, 'price_override' => null]);
        $this->assertDatabaseHas('audit_logs', ['action' => 'product.updated', 'user_id' => $manager->id]);
    }

    public function test_price_audit_failure_rolls_back_the_catalog_mutation(): void
    {
        $admin = User::factory()->create(['business_id' => $this->cashier->business_id]);
        $admin->assignRole('admin');
        $audit = \Mockery::mock(\App\Services\AuditLogService::class);
        $audit->shouldReceive('record')->once()->andThrow(new \RuntimeException('Audit unavailable'));
        $this->app->instance(\App\Services\AuditLogService::class, $audit);
        $this->bearer($admin->createToken('admin')->plainTextToken)->patchJson('/api/v1/products/'.$this->product->id, ['base_price' => 1])->assertServerError();
        $this->assertDatabaseHas('products', ['id' => $this->product->id, 'base_price' => 10]);
    }

    public function test_disabled_electronic_payment_cannot_create_a_paid_order(): void
    {
        config(['payments.allowed_methods' => ['cash']]);
        $this->bearer()->postJson('/api/v1/orders', $this->sale())->assertUnprocessable();
        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('payments', 0);
        $this->assertDatabaseCount('stock_movements', 0);
    }

    public function test_audit_model_rejects_updates_and_deletion(): void
    {
        $event = AuditLog::create(['user_id' => $this->cashier->id, 'action' => 'fixture']);
        foreach (['update', 'delete'] as $action) {
            try {
                if ($action === 'update') $event->update(['action' => 'tampered']);
                else $event->delete();
                $this->fail('Audit mutation was accepted.');
            } catch (\LogicException) {
                $this->assertDatabaseHas('audit_logs', ['id' => $event->id, 'action' => 'fixture']);
            }
        }
    }
}
