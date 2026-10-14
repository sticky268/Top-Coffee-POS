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
}
