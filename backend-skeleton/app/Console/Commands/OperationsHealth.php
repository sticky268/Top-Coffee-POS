<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\{Cache, DB, Schema};
use Throwable;

class OperationsHealth extends Command
{
    protected $signature = 'pos:operations-health {--json : Return only safe check names and booleans}';
    protected $description = 'Read-only DB/cache/disk, failed-job and security-event health signals';

    public function handle(): int
    {
        $checks = [];
        $valid = true;
        foreach (['window_minutes', 'failed_login_limit', 'refund_limit', 'cancel_limit', 'minimum_free_bytes'] as $key) {
            $valid = $valid && is_int(config('operations.'.$key)) && config('operations.'.$key) > 0;
        }
        $checks['thresholds_configured'] = $valid;
        $free = disk_free_space(storage_path());
        $checks['storage_has_capacity'] = $free !== false && $free >= config('operations.minimum_free_bytes');
        try {
            Cache::get('pos:operations-health-probe');
            $checks['cache_available'] = true;
            $checks['persistent_cache'] = ! in_array(config('cache.default'), ['array', 'null'], true);
        } catch (Throwable) {
            $checks['cache_available'] = false;
        }
        try {
            DB::select('SELECT 1');
            $checks['database_available'] = true;
            $since = now()->subMinutes(max(1, (int) config('operations.window_minutes')));
            $checks['audit_schema_available'] = Schema::hasTable('audit_logs');
            if ($checks['audit_schema_available'] && $valid) {
                foreach (['auth.login_failed' => 'failed_login_limit', 'order.refunded' => 'refund_limit', 'order.cancelled' => 'cancel_limit'] as $action => $limit) {
                    $checks[$limit.'_not_reached'] = DB::table('audit_logs')->where('action', $action)
                        ->where('created_at', '>=', $since)->count() < config('operations.'.$limit);
                }
            }
            $checks['failed_job_schema_available'] = Schema::hasTable('failed_jobs');
            if ($checks['failed_job_schema_available']) {
                $checks['no_recent_failed_jobs'] = ! DB::table('failed_jobs')->where('failed_at', '>=', $since)->exists();
            }
        } catch (Throwable) {
            $checks['database_available'] = false;
        }
        $healthy = ! in_array(false, $checks, true);
        $report = ['healthy' => $healthy, 'checks' => $checks];
        if ($this->option('json')) $this->line(json_encode($report, JSON_THROW_ON_ERROR));
        else $this->table(['Check', 'Result'], array_map(fn ($name, $pass) => [$name, $pass ? 'PASS' : 'FAIL'], array_keys($checks), $checks));
        return $healthy ? self::SUCCESS : self::FAILURE;
    }
}
