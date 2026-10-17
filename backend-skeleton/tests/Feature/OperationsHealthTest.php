<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\{Artisan, Cache, DB};
use Tests\TestCase;

class OperationsHealthTest extends TestCase
{
    use RefreshDatabase;

    public function test_check_is_read_only_and_contains_no_event_or_exception_details(): void
    {
        Cache::shouldReceive('get')->once()->with('pos:operations-health-probe')->andReturn(null);
        config(['cache.default' => 'redis', 'operations.minimum_free_bytes' => 1]);
        DB::enableQueryLog();
        $this->assertSame(0, Artisan::call('pos:operations-health', ['--json' => true]));
        $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        foreach (DB::getQueryLog() as $query) {
            $this->assertMatchesRegularExpression('/^\s*(SELECT|SHOW|PRAGMA)\b/i', $query['query']);
        }
        DB::disableQueryLog();
        $this->assertTrue($report['healthy']);
        foreach ($report['checks'] as $value) $this->assertIsBool($value);
    }

    public function test_audit_spike_triggers_failure_without_returning_staff_data(): void
    {
        Cache::shouldReceive('get')->once()->andReturn(null);
        config(['cache.default' => 'redis', 'operations.minimum_free_bytes' => 1, 'operations.failed_login_limit' => 2]);
        foreach ([1, 2] as $i) DB::table('audit_logs')->insert(['action' => 'auth.login_failed', 'created_at' => now()]);
        $this->assertSame(1, Artisan::call('pos:operations-health', ['--json' => true]));
        $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        $this->assertFalse($report['checks']['failed_login_limit_not_reached']);
        $this->assertSame(2, DB::table('audit_logs')->count());
    }

    public function test_cache_errors_and_invalid_thresholds_fail_closed_without_exception_secrets(): void
    {
        Cache::shouldReceive('get')->once()->andThrow(new \RuntimeException('SECRET-CONNECTION-PASSWORD'));
        config(['operations.refund_limit' => 0]);
        $this->assertSame(1, Artisan::call('pos:operations-health', ['--json' => true]));
        $output = Artisan::output();
        $this->assertStringNotContainsString('SECRET-CONNECTION-PASSWORD', $output);
        $report = json_decode($output, true, flags: JSON_THROW_ON_ERROR);
        $this->assertFalse($report['checks']['thresholds_configured']);
        $this->assertFalse($report['checks']['cache_available']);
    }

    public function test_recent_failed_job_triggers_failure_without_logging_its_payload(): void
    {
        Cache::shouldReceive('get')->once()->andReturn(null);
        config(['cache.default' => 'redis', 'operations.minimum_free_bytes' => 1]);
        DB::table('failed_jobs')->insert(['uuid' => (string) \Illuminate\Support\Str::uuid(), 'connection' => 'redis',
            'queue' => 'default', 'payload' => 'PRIVATE-CUSTOMER-PAYLOAD', 'exception' => 'PRIVATE-STACK', 'failed_at' => now()]);
        $this->assertSame(1, Artisan::call('pos:operations-health', ['--json' => true]));
        $output = Artisan::output();
        $this->assertStringNotContainsString('PRIVATE-', $output);
        $this->assertFalse(json_decode($output, true)['checks']['no_recent_failed_jobs']);
    }
}
