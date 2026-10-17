<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Tests\TestCase;

class ProductionCheckTest extends TestCase
{
    use RefreshDatabase;

    public function test_development_environment_cannot_be_reported_ready_for_production(): void
    {
        config(['app.env' => 'local', 'app.debug' => true, 'app.url' => 'http://localhost', 'cache.default' => 'array']);
        $this->assertSame(1, Artisan::call('pos:production-check', ['--json' => true]));
        $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        $this->assertFalse($report['ready']);
        $this->assertFalse($report['checks']['debug_disabled']);
        $this->assertFalse($report['checks']['transactional_database']);
    }
    public function test_demo_accounts_cannot_be_seeded_in_production(): void
    {
        config(['app.env' => 'production']);
        $this->expectException(\LogicException::class);
        (new \Database\Seeders\DatabaseSeeder())->run();
    }

    public function test_readiness_rejects_https_localhost_and_credential_bearing_application_urls(): void
    {
        foreach (['https://localhost', 'https://user:password@coffee.example.com', 'https:/coffee.example.com'] as $url) {
            config(['app.url' => $url]);
            $this->assertSame(1, Artisan::call('pos:production-check', ['--json' => true]));
            $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
            $this->assertFalse($report['checks']['https_application_url']);
            $this->assertStringNotContainsString('password', Artisan::output());
        }
        config(['app.url' => 'https://coffee.example.com']);
        Artisan::call('pos:production-check', ['--json' => true]);
        $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        $this->assertTrue($report['checks']['https_application_url']);
        $this->assertFalse($report['ready'], 'A valid URL alone cannot certify the environment.');
    }

}
