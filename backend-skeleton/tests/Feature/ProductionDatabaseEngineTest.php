<?php

namespace Tests\Feature;

use App\Services\ProductionReadiness;
use Illuminate\Support\Facades\{Artisan, DB, Schema};
use Tests\TestCase;

class ProductionDatabaseEngineTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        if (getenv('RUN_OPERATIONS_RELEASE_CHECKS') !== '1') $this->markTestSkipped('Opt-in disposable MySQL engine check.');
        $this->assertTrue(app()->environment('testing'));
        $this->assertSame('mysql', config('database.default'));
        $this->assertSame('operations_testing', DB::connection()->getDatabaseName());
        $this->assertTrue(Schema::hasTable('orders'));
    }

    public function test_current_mysql_schema_uses_transactional_tables(): void
    {
        $this->assertTrue(app(ProductionReadiness::class)->hasTransactionalTables(DB::connection()));
    }

    public function test_readiness_detects_myisam_without_altering_any_table_or_row(): void
    {
        $this->assertFalse(Schema::hasTable('release_readiness_engine_probe'));
        DB::statement('CREATE TABLE release_readiness_engine_probe (id INT PRIMARY KEY) ENGINE=MyISAM');
        try {
            DB::table('release_readiness_engine_probe')->insert(['id' => 7]);
            DB::enableQueryLog();
            DB::flushQueryLog();
            $this->assertSame(1, Artisan::call('pos:production-check', ['--json' => true]));
            $queries = DB::getQueryLog();
            DB::disableQueryLog();
            $report = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
            $this->assertFalse($report['ready']);
            $this->assertFalse($report['checks']['transactional_database']);
            foreach ($queries as $query) {
                $this->assertMatchesRegularExpression('/^\s*(SELECT|SHOW)\b/i', $query['query'], 'Readiness must be read-only.');
            }
            $this->assertSame([7], DB::table('release_readiness_engine_probe')->pluck('id')->all());
            $engine = DB::selectOne("SELECT ENGINE AS engine FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'release_readiness_engine_probe'");
            $this->assertSame('MyISAM', $engine->engine);
        } finally {
            DB::disableQueryLog();
            Schema::dropIfExists('release_readiness_engine_probe');
        }
    }
}
