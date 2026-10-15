<?php

namespace Tests\Feature;

use App\Models\{Business, User};
use App\Services\OperationsHealthReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\{Artisan, Auth, DB};
use Illuminate\Support\Str;
use Tests\TestCase;

class PilotOperationsTest extends TestCase
{
    use RefreshDatabase;

    public function test_health_endpoint_fails_closed_and_does_not_probe_for_unauthorized_callers(): void
    {
        $this->mock(OperationsHealthReport::class)->shouldNotReceive('report');
        config(['operations.health_token' => null]);
        $this->getJson('/api/v1/operations/health')->assertUnauthorized();
        config(['operations.health_token' => str_repeat('h', 40)]);
        $this->withToken('wrong')->getJson('/api/v1/operations/health')->assertUnauthorized();
    }

    public function test_authorized_monitor_receives_safe_health_results_and_noncacheable_503(): void
    {
        $secret = str_repeat('h', 40);
        config(['operations.health_token' => $secret]);
        $this->mock(OperationsHealthReport::class)->shouldReceive('report')->once()
            ->andReturn(['healthy' => false, 'checks' => ['database_available' => false]]);
        $response = $this->withToken($secret)->getJson('/api/v1/operations/health');
        $response->assertStatus(503)->assertJsonPath('checks.database_available', false);
        $this->assertStringContainsString('no-store', $response->headers->get('Cache-Control'));
        $this->assertStringNotContainsString($secret, $response->getContent());
    }

    public function test_healthy_endpoint_returns_200(): void
    {
        config(['operations.health_token' => str_repeat('h', 40)]);
        $this->mock(OperationsHealthReport::class)->shouldReceive('report')->once()
            ->andReturn(['healthy' => true, 'checks' => ['database_available' => true]]);
        $this->withToken(str_repeat('h', 40))->getJson('/api/v1/operations/health')->assertOk();
    }

    public function test_settings_gate_reports_missing_pin_even_with_safe_cash_and_discount_settings(): void
    {
        $business = Business::factory()->create(['is_active' => true]);
        // The ownership migration also creates a legacy active business.
        Business::query()->update(['require_cash_shift' => true, 'require_manager_controls' => true, 'manager_discount_percent' => 0]);
        config(['payments.allowed_methods' => ['cash'], 'operations.manager_pin_enabled' => true]);
        $this->assertSame(1, Artisan::call('pos:business-settings-check', ['--json' => true]));
        $report = json_decode(Artisan::output(), true);
        $this->assertTrue($report['checks']['cashier_discount_limit_zero']);
        $this->assertTrue($report['checks']['manager_controls_required']);
        $this->assertFalse($report['checks']['manager_pin_enforced_for_void_and_refund']);
        $this->assertFalse($report['ready']);
        $this->assertDatabaseCount('audit_logs', 0);
    }

    public function test_one_unsafe_business_blocks_settings_even_when_another_is_safe(): void
    {
        Business::query()->update(['require_cash_shift' => true, 'require_manager_controls' => true, 'manager_discount_percent' => 0]);
        $unsafe = Business::factory()->create(['is_active' => true]);
        $this->assertSame(1, Artisan::call('pos:business-settings-check', ['--json' => true]));
        $checks = json_decode(Artisan::output(), true)['checks'];
        $this->assertFalse($checks['cashier_discount_limit_zero']);
        $this->assertFalse($checks['manager_controls_required']);
        $this->assertFalse($unsafe->fresh()->require_manager_controls);
    }

    public function test_unsafe_business_settings_fail_without_mutation(): void
    {
        Business::factory()->create(['is_active' => true]);
        config(['payments.allowed_methods' => ['cash', 'card']]);
        $this->assertSame(1, Artisan::call('pos:business-settings-check', ['--json' => true]));
        $checks = json_decode(Artisan::output(), true)['checks'];
        $this->assertFalse($checks['cash_only_default']);
        $this->assertFalse($checks['cash_shift_required']);
        $this->assertFalse($checks['manager_controls_required']);
    }

    public function test_revoked_device_token_is_rejected_immediately_but_peer_installation_survives(): void
    {
        $user = User::factory()->create();
        $device = (string) Str::uuid();
        $lost = $user->createToken('device:'.strtoupper($device))->plainTextToken;
        $other = User::factory()->create();
        $other->createToken('device:'.$device);
        $peer = $user->createToken('device:'.Str::uuid())->plainTextToken;
        $this->withToken($lost)->getJson('/api/v1/auth/sessions')->assertOk();
        $this->assertSame(0, Artisan::call('pos:revoke-device', ['user' => $user->id, 'device' => $device, '--reason' => 'INC-DRILL']));
        Auth::forgetGuards();
        $this->withToken($lost)->getJson('/api/v1/auth/sessions')->assertUnauthorized();
        Auth::forgetGuards();
        $this->withToken($peer)->getJson('/api/v1/auth/sessions')->assertOk();
        $this->assertSame(1, $other->tokens()->count());
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.device_revoked', 'business_id' => $user->business_id]);
        $this->assertStringNotContainsString($lost, json_encode(DB::table('audit_logs')->get()));
        $this->assertSame(0, Artisan::call('pos:revoke-device', ['user' => $user->id, 'device' => $device, '--reason' => 'INC-DRILL-RETRY']));
    }
}
