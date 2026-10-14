<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Encryption\Encrypter;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Schema;
use Throwable;

class ProductionCheck extends Command
{
    protected $signature = 'pos:production-check {--json : Return machine-readable results}';
    protected $description = 'Read-only production configuration and migration checks';

    public function handle(): int
    {
        $key = (string) config('app.key');
        if (str_starts_with($key, 'base64:')) $key = base64_decode(substr($key, 7), true) ?: '';
        $checks = [
            'production_environment' => config('app.env') === 'production',
            'debug_disabled' => config('app.debug') === false,
            'application_key_valid' => Encrypter::supported($key, config('app.cipher')),
            'https_application_url' => parse_url(config('app.url'), PHP_URL_SCHEME) === 'https',
            'persistent_cache' => ! in_array(config('cache.default'), ['array', 'null'], true),
        ];
        try {
            Cache::get('pos:production-readiness-probe');
            $checks['cache_available'] = true;
        } catch (Throwable) {
            $checks['cache_available'] = false;
        }
        try {
            DB::select('SELECT 1');
            $checks['transactional_database'] = in_array(DB::connection()->getDriverName(), ['mysql', 'pgsql'], true);
            $ran = Schema::hasTable('migrations') ? DB::table('migrations')->pluck('migration')->all() : [];
            $required = array_map(fn ($path) => basename($path, '.php'), glob(database_path('migrations/*.php')) ?: []);
            $checks['migrations_current'] = count(array_diff($required, $ran)) === 0;
            $checks['business_ownership_verified'] = app(\App\Services\TenantIntegrity::class)->report()['ready'];
            $checks['kitchen_schema_removed'] = ! Schema::hasTable('kitchen_tickets')
                && ! Schema::hasTable('kitchen_ticket_items')
                && ! Schema::hasTable('kitchen_item_voids')
                && ! Schema::hasColumn('branches', 'use_kitchen_display');
        } catch (Throwable) {
            $checks['database_available'] = false;
        }
        if ($this->option('json')) {
            $this->line(json_encode(['ready' => ! in_array(false, $checks, true), 'checks' => $checks], JSON_THROW_ON_ERROR));
        } else {
            $this->table(['Check', 'Result'], array_map(fn ($name, $passed) => [$name, $passed ? 'PASS' : 'FAIL'], array_keys($checks), $checks));
        }
        return in_array(false, $checks, true) ? self::FAILURE : self::SUCCESS;
    }
}
